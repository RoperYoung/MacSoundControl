import AppKit
import Accelerate
import AudioToolbox
import AVFoundation
import CoreMedia
import ServiceManagement

final class MicKeeper: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    enum State {
        case waitingForPermission
        case starting(deviceID: String, deviceName: String)
        case running(deviceID: String, deviceName: String)
        case interrupted(deviceID: String, deviceName: String)
        case stopped
        case permissionDenied
        case failed(message: String)
    }

    var onStateChange: ((State) -> Void)?
    var onAudioLevel: ((MicrophoneAudioLevel) -> Void)?

    private let sessionQueue = DispatchQueue(
        label: "cn.neohub.macsoundcontrol.capture-session",
        qos: .userInitiated
    )
    private let sampleQueue = DispatchQueue(
        label: "cn.neohub.macsoundcontrol.audio-sink",
        qos: .utility
    )
    private let requestLock = NSLock()
    private let levelMonitoringLock = NSLock()
    private let levelDeliveryLock = NSLock()

    private var latestRequestID = 0
    private var session: AVCaptureSession?
    private var activeOutput: AVCaptureAudioDataOutput?
    private var activeRequestID: Int?
    private var activeDeviceID: String?
    private var activeDeviceName: String?
    private var hasReceivedFirstBuffer = false
    private var isInterrupted = false
    private var firstBufferWatchdogGeneration = 0
    private var livenessWatchdogGeneration = 0
    private var lastBufferUptime: TimeInterval?
    private var sessionObservers: [NSObjectProtocol] = []
    private var isLevelMonitoringEnabled = false
    private var lastLevelReportUptime: TimeInterval = 0
    private var levelScratchSamples: [Float] = []
    private var pendingAudioLevel: MicrophoneAudioLevel?
    private var isAudioLevelDeliveryScheduled = false

    static func audioDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        )
        .devices
        .sorted {
            $0.localizedName.localizedStandardCompare($1.localizedName) == .orderedAscending
        }
    }

    func start(preferredDeviceID: String?) {
        let requestID = makeRequest()

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            startAuthorized(preferredDeviceID: preferredDeviceID, requestID: requestID)
        case .notDetermined:
            report(.waitingForPermission, requestID: requestID)
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                guard let self, self.isLatestRequest(requestID) else { return }
                if granted {
                    self.startAuthorized(
                        preferredDeviceID: preferredDeviceID,
                        requestID: requestID
                    )
                } else {
                    self.report(.permissionDenied, requestID: requestID)
                }
            }
        case .denied, .restricted:
            report(.permissionDenied, requestID: requestID)
        @unknown default:
            report(.failed(message: "无法读取麦克风权限状态"), requestID: requestID)
        }
    }

    func stop() {
        let requestID = makeRequest()
        sessionQueue.async { [weak self] in
            guard let self, self.isLatestRequest(requestID) else { return }
            self.stopSessionLocked()
            self.report(.stopped, requestID: requestID)
        }
    }

    func restart(preferredDeviceID: String?) {
        start(preferredDeviceID: preferredDeviceID)
    }

    func setLevelMonitoringEnabled(_ enabled: Bool) {
        levelMonitoringLock.lock()
        isLevelMonitoringEnabled = enabled
        levelMonitoringLock.unlock()

        if !enabled {
            levelDeliveryLock.lock()
            pendingAudioLevel = nil
            levelDeliveryLock.unlock()
        }
    }

    private func startAuthorized(preferredDeviceID: String?, requestID: Int) {
        sessionQueue.async { [weak self] in
            guard let self, self.isLatestRequest(requestID) else { return }

            self.stopSessionLocked()

            let devices = Self.audioDevices()
            let selectedDevice: AVCaptureDevice?
            if let preferredDeviceID {
                selectedDevice = devices.first(where: {
                    $0.uniqueID == preferredDeviceID
                })
            } else {
                selectedDevice = AVCaptureDevice.default(for: .audio) ?? devices.first
            }

            guard let selectedDevice else {
                let message = preferredDeviceID == nil
                    ? "没有找到可用的麦克风"
                    : "系统麦克风暂时还没有准备好，正在重试"
                self.report(.failed(message: message), requestID: requestID)
                return
            }

            do {
                let input = try AVCaptureDeviceInput(device: selectedDevice)
                let output = AVCaptureAudioDataOutput()
                output.audioSettings = [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVLinearPCMBitDepthKey: 32,
                    AVLinearPCMIsFloatKey: true,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsNonInterleaved: false
                ]
                output.setSampleBufferDelegate(self, queue: self.sampleQueue)

                let newSession = AVCaptureSession()
                newSession.beginConfiguration()

                guard newSession.canAddInput(input) else {
                    newSession.commitConfiguration()
                    self.report(
                        .failed(message: "无法打开 \(selectedDevice.localizedName)"),
                        requestID: requestID
                    )
                    return
                }
                newSession.addInput(input)

                guard newSession.canAddOutput(output) else {
                    newSession.commitConfiguration()
                    self.report(
                        .failed(message: "无法创建麦克风音频流"),
                        requestID: requestID
                    )
                    return
                }
                newSession.addOutput(output)
                newSession.commitConfiguration()

                guard self.isLatestRequest(requestID) else { return }

                self.session = newSession
                self.activeOutput = output
                self.activeRequestID = requestID
                self.activeDeviceID = selectedDevice.uniqueID
                self.activeDeviceName = selectedDevice.localizedName
                self.hasReceivedFirstBuffer = false
                self.isInterrupted = false
                self.observeSession(newSession, requestID: requestID)

                self.report(
                    .starting(
                        deviceID: selectedDevice.uniqueID,
                        deviceName: selectedDevice.localizedName
                    ),
                    requestID: requestID
                )

                newSession.startRunning()

                guard self.isLatestRequest(requestID),
                      self.session === newSession else {
                    self.stopSessionLocked()
                    return
                }

                guard newSession.isRunning else {
                    self.stopSessionLocked()
                    self.report(
                        .failed(message: "\(selectedDevice.localizedName) 启动失败"),
                        requestID: requestID
                    )
                    return
                }

                self.scheduleFirstBufferWatchdog(requestID: requestID)
            } catch {
                self.stopSessionLocked()
                self.report(.failed(message: error.localizedDescription), requestID: requestID)
            }
        }
    }

    private func observeSession(_ observedSession: AVCaptureSession, requestID: Int) {
        let center = NotificationCenter.default

        sessionObservers.append(
            center.addObserver(
                forName: AVCaptureSession.runtimeErrorNotification,
                object: observedSession,
                queue: nil
            ) { [weak self, weak observedSession] notification in
                guard let self, let observedSession else { return }
                let error = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError
                self.sessionQueue.async {
                    guard self.isLatestRequest(requestID),
                          self.session === observedSession else { return }
                    self.stopSessionLocked()
                    self.report(
                        .failed(message: error?.localizedDescription ?? "麦克风输入发生错误"),
                        requestID: requestID
                    )
                }
            }
        )

        sessionObservers.append(
            center.addObserver(
                forName: AVCaptureSession.didStopRunningNotification,
                object: observedSession,
                queue: nil
            ) { [weak self, weak observedSession] _ in
                guard let self, let observedSession else { return }
                self.sessionQueue.async {
                    guard self.isLatestRequest(requestID),
                          self.session === observedSession else { return }
                    self.stopSessionLocked()
                    self.report(
                        .failed(message: "麦克风输入通道意外停止，正在重试"),
                        requestID: requestID
                    )
                }
            }
        )

        sessionObservers.append(
            center.addObserver(
                forName: AVCaptureSession.wasInterruptedNotification,
                object: observedSession,
                queue: nil
            ) { [weak self, weak observedSession] _ in
                guard let self, let observedSession else { return }
                self.sessionQueue.async {
                    guard self.isLatestRequest(requestID),
                          self.session === observedSession,
                          let deviceID = self.activeDeviceID,
                          let deviceName = self.activeDeviceName else { return }
                    self.isInterrupted = true
                    self.hasReceivedFirstBuffer = false
                    self.invalidateFirstBufferWatchdogLocked()
                    self.invalidateLivenessWatchdogLocked()
                    self.report(
                        .interrupted(deviceID: deviceID, deviceName: deviceName),
                        requestID: requestID
                    )
                }
            }
        )

        sessionObservers.append(
            center.addObserver(
                forName: AVCaptureSession.interruptionEndedNotification,
                object: observedSession,
                queue: nil
            ) { [weak self, weak observedSession] _ in
                guard let self, let observedSession else { return }
                self.sessionQueue.async {
                    guard self.isLatestRequest(requestID),
                          self.session === observedSession,
                          let deviceID = self.activeDeviceID,
                          let deviceName = self.activeDeviceName else { return }
                    self.isInterrupted = false
                    self.hasReceivedFirstBuffer = false
                    self.report(
                        .starting(deviceID: deviceID, deviceName: deviceName),
                        requestID: requestID
                    )
                    self.scheduleFirstBufferWatchdog(requestID: requestID)
                }
            }
        )
    }

    private func scheduleFirstBufferWatchdog(requestID: Int) {
        firstBufferWatchdogGeneration += 1
        let watchdogGeneration = firstBufferWatchdogGeneration
        sessionQueue.asyncAfter(deadline: .now() + 8.0) { [weak self] in
            guard let self,
                  self.firstBufferWatchdogGeneration == watchdogGeneration,
                  self.isLatestRequest(requestID),
                  self.session != nil,
                  !self.isInterrupted,
                  !self.hasReceivedFirstBuffer else { return }
            let deviceName = self.activeDeviceName ?? "麦克风"
            self.stopSessionLocked()
            self.report(
                .failed(message: "\(deviceName) 没有送来音频，正在重试"),
                requestID: requestID
            )
        }
    }

    private func scheduleLivenessWatchdog(requestID: Int) {
        livenessWatchdogGeneration += 1
        let watchdogGeneration = livenessWatchdogGeneration
        runLivenessCheck(
            requestID: requestID,
            watchdogGeneration: watchdogGeneration
        )
    }

    private func runLivenessCheck(requestID: Int, watchdogGeneration: Int) {
        sessionQueue.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self,
                  self.livenessWatchdogGeneration == watchdogGeneration,
                  self.isLatestRequest(requestID),
                  self.session != nil else { return }

            if self.isInterrupted {
                return
            }

            let elapsed = ProcessInfo.processInfo.systemUptime -
                (self.lastBufferUptime ?? 0)
            if elapsed > 5.0 {
                let deviceName = self.activeDeviceName ?? "麦克风"
                self.stopSessionLocked()
                self.report(
                    .failed(message: "\(deviceName) 已停止送来音频，正在重试"),
                    requestID: requestID
                )
                return
            }

            self.runLivenessCheck(
                requestID: requestID,
                watchdogGeneration: watchdogGeneration
            )
        }
    }

    private func invalidateFirstBufferWatchdogLocked() {
        firstBufferWatchdogGeneration += 1
    }

    private func invalidateLivenessWatchdogLocked() {
        livenessWatchdogGeneration += 1
    }

    private func stopSessionLocked() {
        invalidateFirstBufferWatchdogLocked()
        invalidateLivenessWatchdogLocked()
        for observer in sessionObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        sessionObservers.removeAll()

        if let session, session.isRunning {
            session.stopRunning()
        }
        session = nil
        activeOutput = nil
        activeRequestID = nil
        activeDeviceID = nil
        activeDeviceName = nil
        hasReceivedFirstBuffer = false
        isInterrupted = false
        lastBufferUptime = nil
    }

    private func makeRequest() -> Int {
        requestLock.lock()
        latestRequestID += 1
        let requestID = latestRequestID
        requestLock.unlock()
        return requestID
    }

    private func isLatestRequest(_ requestID: Int) -> Bool {
        requestLock.lock()
        let isLatest = latestRequestID == requestID
        requestLock.unlock()
        return isLatest
    }

    private func report(_ state: State, requestID: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isLatestRequest(requestID) else { return }
            self.onStateChange?(state)
        }
    }

    private func shouldReportAudioLevel() -> Bool {
        levelMonitoringLock.lock()
        let shouldReport = isLevelMonitoringEnabled
        levelMonitoringLock.unlock()
        return shouldReport
    }

    private func audioLevel(
        from sampleBuffer: CMSampleBuffer
    ) -> MicrophoneAudioLevel? {
        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return nil
        }

        let byteLength = CMBlockBufferGetDataLength(dataBuffer)
        let sampleCount = byteLength / MemoryLayout<Float>.size
        guard sampleCount > 0 else { return nil }

        let copiedByteLength = sampleCount * MemoryLayout<Float>.size
        var lengthAtOffset = 0
        var totalLength = 0
        var directDataPointer: UnsafeMutablePointer<Int8>?
        let pointerStatus = CMBlockBufferGetDataPointer(
            dataBuffer,
            atOffset: 0,
            lengthAtOffsetOut: &lengthAtOffset,
            totalLengthOut: &totalLength,
            dataPointerOut: &directDataPointer
        )

        var rootMeanSquare: Float = 0
        if pointerStatus == noErr,
           lengthAtOffset >= copiedByteLength,
           totalLength >= copiedByteLength,
           let directDataPointer {
            let samples = UnsafeRawPointer(directDataPointer)
                .assumingMemoryBound(to: Float.self)
            vDSP_rmsqv(
                samples,
                1,
                &rootMeanSquare,
                vDSP_Length(sampleCount)
            )
            return MicrophoneAudioLevel(rootMeanSquare: rootMeanSquare)
        }

        if levelScratchSamples.count != sampleCount {
            levelScratchSamples = [Float](repeating: 0, count: sampleCount)
        }
        let copyStatus = levelScratchSamples.withUnsafeMutableBytes { bytes in
            CMBlockBufferCopyDataBytes(
                dataBuffer,
                atOffset: 0,
                dataLength: copiedByteLength,
                destination: bytes.baseAddress!
            )
        }
        guard copyStatus == noErr else { return nil }

        levelScratchSamples.withUnsafeBufferPointer { samples in
            guard let baseAddress = samples.baseAddress else { return }
            vDSP_rmsqv(
                baseAddress,
                1,
                &rootMeanSquare,
                vDSP_Length(sampleCount)
            )
        }
        return MicrophoneAudioLevel(rootMeanSquare: rootMeanSquare)
    }

    private func enqueueAudioLevelDelivery(_ level: MicrophoneAudioLevel) {
        levelDeliveryLock.lock()
        pendingAudioLevel = level
        let shouldSchedule = !isAudioLevelDeliveryScheduled
        if shouldSchedule {
            isAudioLevelDeliveryScheduled = true
        }
        levelDeliveryLock.unlock()

        guard shouldSchedule else { return }
        DispatchQueue.main.async { [weak self] in
            self?.deliverLatestAudioLevel()
        }
    }

    private func deliverLatestAudioLevel() {
        levelDeliveryLock.lock()
        let level = pendingAudioLevel
        pendingAudioLevel = nil
        isAudioLevelDeliveryScheduled = false
        levelDeliveryLock.unlock()

        if let level {
            onAudioLevel?(level)
        }
    }

    // Audio buffers intentionally go nowhere: nothing is saved, transmitted, or played.
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        var sampledLevel: MicrophoneAudioLevel?
        if shouldReportAudioLevel() {
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastLevelReportUptime >= 1.0 / 60.0,
               let level = audioLevel(from: sampleBuffer) {
                lastLevelReportUptime = now
                sampledLevel = level
            }
        }

        sessionQueue.async { [weak self, weak output, sampledLevel] in
            guard let self,
                  let output,
                  self.activeOutput === output,
                  let requestID = self.activeRequestID,
                  self.isLatestRequest(requestID),
                  let deviceID = self.activeDeviceID,
                  let deviceName = self.activeDeviceName else { return }

            if let sampledLevel, self.shouldReportAudioLevel() {
                self.enqueueAudioLevelDelivery(sampledLevel)
            }

            self.lastBufferUptime = ProcessInfo.processInfo.systemUptime
            self.isInterrupted = false
            if !self.hasReceivedFirstBuffer {
                self.hasReceivedFirstBuffer = true
                self.invalidateFirstBufferWatchdogLocked()
                self.scheduleLivenessWatchdog(requestID: requestID)
                self.report(
                    .running(deviceID: deviceID, deviceName: deviceName),
                    requestID: requestID
                )
            }
        }
    }
}

private enum MicrophoneTestState {
    case idle
    case preparing(deviceUID: String)
    case testing(deviceUID: String)
    case failed(deviceUID: String?, message: String)

    var isActive: Bool {
        switch self {
        case .preparing, .testing:
            return true
        case .idle, .failed:
            return false
        }
    }

    var deviceUID: String? {
        switch self {
        case .idle:
            return nil
        case .preparing(let deviceUID),
             .testing(let deviceUID):
            return deviceUID
        case .failed(let deviceUID, _):
            return deviceUID
        }
    }
}

private enum PersistentDeviceMenuDirection {
    case input
    case output

    var presentationDirection: AudioDevicePresentationDirection {
        switch self {
        case .input:
            return .input
        case .output:
            return .output
        }
    }
}

private struct PersistentDeviceMenuEntry {
    let uid: String
    let isVirtual: Bool
    let item: NSMenuItem
    let view: PersistentMenuActionView
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static let menuContentWidth: CGFloat = 460
    private static let applicationVolumeRowHeight: CGFloat = 38
    private static let sectionHeaderHeight: CGFloat = 28
    private static let deviceRowHeight: CGFloat = 42
    private static let outputApplicationSectionSpacing: CGFloat = 10
    private static let customStatusBarIconSize = NSSize(width: 17, height: 17)

    private let keeper = MicKeeper()
    private let audioDevices = AudioDeviceManager()
    private let applicationVolumes = ApplicationVolumeControllerFactory.make()
    private let defaults = UserDefaults.standard

    private lazy var customStatusBarIcon: NSImage? = {
        guard let url = Bundle.main.url(
            forResource: "StatusBarIcon",
            withExtension: "svg"
        ), let image = NSImage(contentsOf: url) else {
            return nil
        }

        image.size = Self.customStatusBarIconSize
        image.isTemplate = true
        return image
    }()

    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var keeperState: MicKeeper.State = .stopped
    private var keeperRequestedUID: String?
    private var transientMessage: String?
    private var transientMessageToken = 0
    private var retryWorkItem: DispatchWorkItem?
    private var systemSyncWorkItem: DispatchWorkItem?
    private var monitoringRetryWorkItem: DispatchWorkItem?
    private var retryAttempt = 0
    private var monitoringRetryAttempt = 0
    private var lastSynchronizedSystemUID: String?
    private var isSleeping = false
    private var workspaceObservers: [NSObjectProtocol] = []
    private var microphoneTestState: MicrophoneTestState = .idle
    private var mainWindowController: MainWindowController?
    private weak var outputVolumeView: OutputVolumeMenuView?
    private var outputVolumeControlDevice: AudioDevice?
    private var outputVolumeInteraction = OutputVolumeInteractionState()
    private var outputVolumeReadbackWorkItem: DispatchWorkItem?
    private var lastApplicationVolumeSupportState: ApplicationVolumeSupportState?
    private var isMainApplicationVolumeTracking = false
    private var inputDeviceMenuEntries: [PersistentDeviceMenuEntry] = []
    private var outputDeviceMenuEntries: [PersistentDeviceMenuEntry] = []
    private var inputEmptyMenuItem: NSMenuItem?
    private var outputEmptyMenuItem: NSMenuItem?
    private var keepAliveMenuView: PersistentMenuActionView?
    private var virtualDevicesMenuView: PersistentMenuActionView?
    private var launchAtLoginMenuView: PersistentMenuActionView?
    private weak var applicationVolumeHeaderView: ApplicationVolumeHeaderView?
    private var applicationVolumeDetailItems: [NSMenuItem] = []
    private var isOutputSelectionInFlight = false

    private var microphoneKeepAliveEnabled: Bool {
        get {
            if defaults.object(forKey: "keepAliveEnabled") == nil {
                return true
            }
            return defaults.bool(forKey: "keepAliveEnabled")
        }
        set {
            defaults.set(newValue, forKey: "keepAliveEnabled")
        }
    }

    private var showVirtualDevices: Bool {
        get {
            guard defaults.object(forKey: "showVirtualDevices") != nil else {
                return false
            }
            return defaults.bool(forKey: "showVirtualDevices")
        }
        set {
            defaults.set(newValue, forKey: "showVirtualDevices")
        }
    }

    private var applicationVolumeControlMode: ApplicationVolumeControlMode {
        get {
            ApplicationVolumeControlMode.load(from: defaults)
        }
        set {
            newValue.save(to: defaults)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // v1 stored an independent capture target. v2 follows the real system input.
        defaults.removeObject(forKey: "preferredDeviceID")

        configureStatusItem()
        observeWorkspace()

        keeper.onStateChange = { [weak self] state in
            self?.apply(keeperState: state)
        }
        keeper.onAudioLevel = { [weak self] level in
            self?.applyMicrophoneTestLevel(level)
        }
        audioDevices.onAudioSystemChanged = { [weak self] in
            guard let self else { return }
            self.refreshOutputVolumeView()
            self.applicationVolumes.handleExternalOutputRouteChange(
                outputDeviceUID: self.audioDevices.defaultOutputDevice()?.uid
            )
            self.updatePresentation()
            self.scheduleSystemSync(after: 0.35, forceRestart: false)
        }
        audioDevices.onOutputVolumeChanged = { [weak self] in
            guard let self else { return }
            if self.refreshOutputVolumeView() {
                self.refreshMainWindowPresentation()
            }
        }
        applicationVolumes.onChange = { [weak self] in
            self?.handleApplicationVolumeChange()
        }
        applicationVolumes.setIndividualControlEnabled(
            applicationVolumeControlMode == .separate
        )
        ensureAudioMonitoring()
        applicationVolumes.start(
            outputDeviceUID: audioDevices.defaultOutputDevice()?.uid
        )

        synchronizeWithSystemInput(forceRestart: true)

        #if DEBUG
        if CommandLine.arguments.contains("--show-main-window") {
            DispatchQueue.main.async { [weak self] in
                self?.presentMainWindow(destination: .outputVolume)
                if CommandLine.arguments.contains("--reference-viewport") {
                    self?.mainWindowController?.setReferenceViewportForVisualQA()
                }
            }
        }
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        retryWorkItem?.cancel()
        systemSyncWorkItem?.cancel()
        monitoringRetryWorkItem?.cancel()
        outputVolumeReadbackWorkItem?.cancel()
        outputVolumeReadbackWorkItem = nil
        mainWindowController?.close()
        mainWindowController = nil
        keeper.setLevelMonitoringEnabled(false)
        applicationVolumes.stop()
        audioDevices.stopMonitoring()
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        keeper.stop()
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        menu.minimumWidth = Self.menuContentWidth
        statusItem.menu = menu
        updatePresentation()
        rebuildMenu()
    }

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter

        workspaceObservers.append(
            center.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                self.isSleeping = true
                self.retryWorkItem?.cancel()
                self.systemSyncWorkItem?.cancel()
                self.monitoringRetryWorkItem?.cancel()
                self.monitoringRetryWorkItem = nil
                self.outputVolumeReadbackWorkItem?.cancel()
                self.outputVolumeReadbackWorkItem = nil
                self.outputVolumeInteraction.reset()
                self.microphoneTestState = .idle
                self.keeper.setLevelMonitoringEnabled(false)
                self.applicationVolumes.stop()
                self.keeperRequestedUID = nil
                self.keeper.stop()
            }
        )

        workspaceObservers.append(
            center.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                self.isSleeping = false
                self.retryAttempt = 0
                self.monitoringRetryAttempt = 0
                self.applicationVolumes.start(
                    outputDeviceUID: self.audioDevices.defaultOutputDevice()?.uid
                )
                self.scheduleSystemSync(after: 1.8, forceRestart: true)
            }
        )
    }

    func menuWillOpen(_ menu: NSMenu) {
        applicationVolumes.refresh()
        rebuildMenu()
    }

    private func rebuildMenu() {
        guard menu != nil else { return }
        inputDeviceMenuEntries.removeAll()
        outputDeviceMenuEntries.removeAll()
        inputEmptyMenuItem = nil
        outputEmptyMenuItem = nil
        keepAliveMenuView = nil
        virtualDevicesMenuView = nil
        launchAtLoginMenuView = nil
        applicationVolumeHeaderView = nil
        applicationVolumeDetailItems.removeAll()
        menu.removeAllItems()

        let currentInput = audioDevices.defaultInputDevice()
        let currentOutput = audioDevices.defaultOutputDevice()

        addOutputVolumeControl(for: currentOutput)
        addVerticalMenuSpacing(Self.outputApplicationSectionSpacing)
        addApplicationVolumeSection()
        menu.addItem(.separator())

        addDeviceSection(
            title: "选择系统输出",
            devices: audioDevices.outputDevices(),
            current: currentOutput,
            direction: .output,
            emptyTitle: "没有可显示的输出设备",
            purpose: "系统输出"
        )

        menu.addItem(.separator())

        addDeviceSection(
            title: "选择系统输入",
            devices: audioDevices.inputDevices(),
            current: currentInput,
            direction: .input,
            emptyTitle: "没有可显示的输入设备",
            purpose: "系统输入"
        )

        menu.addItem(.separator())

        keepAliveMenuView = addPersistentActionItem(
            title: "开启麦克风常驻",
            isSelected: microphoneKeepAliveEnabled,
            toolTip: "持续打开当前系统输入通道；再次点击即可关闭"
        ) { [weak self] in
            self?.toggleMicrophoneKeepAlive()
        }

        virtualDevicesMenuView = addPersistentActionItem(
            title: "展示虚拟设备",
            isSelected: showVirtualDevices,
            toolTip: "同时显示或隐藏系统输入与输出中的虚拟音频设备"
        ) { [weak self] in
            self?.toggleShowVirtualDevices()
        }

        launchAtLoginMenuView = addPersistentActionItem(
            title: "开机自动启动",
            isSelected: SMAppService.mainApp.status == .enabled,
            toolTip: launchAtLoginToolTip()
        ) { [weak self] in
            self?.toggleLaunchAtLogin()
        }

        if case .permissionDenied = keeperState {
            let privacyItem = NSMenuItem(
                title: "打开麦克风权限设置…",
                action: #selector(openMicrophonePrivacySettings),
                keyEquivalent: ""
            )
            privacyItem.target = self
            addTextColumnAlignedMenuItem(privacyItem)
        }

        menu.addItem(.separator())

        let testItem = NSMenuItem(
            title: "声音输入测试",
            action: #selector(openMicrophoneTestInMainWindow),
            keyEquivalent: ""
        )
        testItem.target = self
        testItem.isEnabled = currentInput != nil
        testItem.toolTip = currentInput.map {
            "在主界面中实时显示 \($0.name) 的输入电平"
        } ?? "当前没有可用的系统输入"
        addTextColumnAlignedMenuItem(testItem)

        if currentInput != nil, microphoneKeepAliveEnabled {
            let reconnectItem = NSMenuItem(
                title: "重新打开当前输入通道",
                action: #selector(reconnectCurrentInput),
                keyEquivalent: "r"
            )
            reconnectItem.target = self
            addTextColumnAlignedMenuItem(reconnectItem)
        }

        menu.addItem(.separator())

        let mainWindowItem = NSMenuItem(
            title: "打开主界面",
            action: #selector(openMainWindow),
            keyEquivalent: ""
        )
        mainWindowItem.target = self
        mainWindowItem.toolTip = "打开完整音频控制、声音输入测试与关于 MacSoundControl"
        addTextColumnAlignedMenuItem(mainWindowItem)

        let quitItem = NSMenuItem(
            title: "退出程序",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        addTextColumnAlignedMenuItem(quitItem)

        refreshPersistentMenuPresentation()
    }

    private func addDeviceSection(
        title: String,
        devices: [AudioDevice],
        current: AudioDevice?,
        direction: PersistentDeviceMenuDirection,
        emptyTitle: String,
        purpose: String
    ) {
        let headerItem = NSMenuItem()
        headerItem.isEnabled = false
        headerItem.toolTip = current.map {
            "当前\(purpose)：\($0.name)"
        } ?? "当前没有可用的\(purpose)设备"
        let headerView = MenuSectionHeaderView(
            frame: NSRect(
                x: 0,
                y: 0,
                width: Self.menuContentWidth,
                height: Self.sectionHeaderHeight
            ),
            title: title
        )
        headerView.toolTip = headerItem.toolTip
        headerItem.view = headerView
        menu.addItem(headerItem)

        for device in devices {
            let item = NSMenuItem()
            let rowView = PersistentMenuActionView(
                frame: NSRect(
                    x: 0,
                    y: 0,
                    width: Self.menuContentWidth,
                    height: Self.deviceRowHeight
                ),
                title: device.name,
                isSelected: current?.uid == device.uid,
                style: .device(
                    symbolName: AudioDevicePresentation.symbolName(
                        deviceName: device.name,
                        transportType: device.transportType,
                        direction: direction.presentationDirection
                    ),
                    detail: device.transportName
                )
            )
            item.representedObject = device.uid
            let toolTip = "\(device.name)，\(device.menuDetail)。点击后设为 macOS \(purpose)，菜单会保持打开。"
            item.toolTip = toolTip
            rowView.configure(toolTip: toolTip)
            rowView.onActivate = { [weak self] in
                self?.selectSystemDevice(direction: direction, uid: device.uid)
            }
            item.view = rowView
            item.isHidden = device.isVirtual && !showVirtualDevices
            menu.addItem(item)

            let entry = PersistentDeviceMenuEntry(
                uid: device.uid,
                isVirtual: device.isVirtual,
                item: item,
                view: rowView
            )
            switch direction {
            case .input:
                inputDeviceMenuEntries.append(entry)
            case .output:
                outputDeviceMenuEntries.append(entry)
            }
        }

        let empty = NSMenuItem(title: emptyTitle, action: nil, keyEquivalent: "")
        empty.isEnabled = false
        let entries = direction == .input
            ? inputDeviceMenuEntries
            : outputDeviceMenuEntries
        empty.isHidden = entries.contains { !$0.item.isHidden }
        menu.addItem(empty)

        switch direction {
        case .input:
            inputEmptyMenuItem = empty
        case .output:
            outputEmptyMenuItem = empty
        }
    }

    @discardableResult
    private func addPersistentActionItem(
        title: String,
        isSelected: Bool,
        toolTip: String,
        action: @escaping () -> Void
    ) -> PersistentMenuActionView {
        let item = NSMenuItem()
        let rowView = PersistentMenuActionView(
            frame: NSRect(
                x: 0,
                y: 0,
                width: Self.menuContentWidth,
                height: 30
            ),
            title: title,
            isSelected: isSelected
        )
        rowView.configure(toolTip: toolTip)
        rowView.onActivate = action
        item.view = rowView
        item.toolTip = toolTip
        menu.addItem(item)
        return rowView
    }

    private func addTextColumnAlignedMenuItem(_ item: NSMenuItem) {
        // A visible native checkmark already reserves the leading state column.
        // Plain and unchecked items need one indentation level to reach the same
        // title position as device rows and PersistentMenuActionView.
        item.indentationLevel = item.state == .off ? 1 : 0
        item.attributedTitle = NSAttributedString(
            string: item.title,
            attributes: [
                .font: NSFont.menuFont(ofSize: 13.5),
                .foregroundColor: NSColor.labelColor,
            ]
        )
        menu.addItem(item)
    }

    private func addVerticalMenuSpacing(_ height: CGFloat) {
        guard height > 0 else { return }

        let item = NSMenuItem()
        item.isEnabled = false
        let spacingView = NSView(
            frame: NSRect(
                x: 0,
                y: 0,
                width: Self.menuContentWidth,
                height: height
            )
        )
        spacingView.setAccessibilityElement(false)
        item.view = spacingView
        menu.addItem(item)
    }

    private func refreshPersistentMenuPresentation() {
        let currentInput = audioDevices.defaultInputDevice()
        let currentOutput = audioDevices.defaultOutputDevice()

        for entry in inputDeviceMenuEntries {
            entry.view.configure(
                isSelected: entry.uid == currentInput?.uid,
                isEnabled: true
            )
        }
        for entry in outputDeviceMenuEntries {
            entry.view.configure(
                isSelected: entry.uid == currentOutput?.uid,
                isEnabled: !isOutputSelectionInFlight
            )
        }

        keepAliveMenuView?.configure(
            isSelected: microphoneKeepAliveEnabled,
            isEnabled: true
        )
        virtualDevicesMenuView?.configure(
            isSelected: showVirtualDevices,
            isEnabled: true
        )
        launchAtLoginMenuView?.configure(
            title: "开机自动启动",
            isSelected: SMAppService.mainApp.status == .enabled,
            isEnabled: true,
            toolTip: launchAtLoginToolTip()
        )
        refreshDeviceSectionEmptyStates()
    }

    private func updateVirtualDeviceVisibility() {
        for entry in inputDeviceMenuEntries + outputDeviceMenuEntries {
            entry.item.isHidden = entry.isVirtual && !showVirtualDevices
        }
        refreshDeviceSectionEmptyStates()
        updateMenuLayoutAndPointerHighlights()
    }

    private func persistentMenuActionViews() -> [PersistentMenuActionView] {
        var views = inputDeviceMenuEntries.map(\.view)
        views.append(contentsOf: outputDeviceMenuEntries.map(\.view))
        views.append(contentsOf: [
            keepAliveMenuView,
            virtualDevicesMenuView,
            launchAtLoginMenuView,
        ].compactMap { $0 })
        return views
    }

    private func updateMenuLayoutAndPointerHighlights() {
        let viewsBeforeLayout = persistentMenuActionViews()
        for view in viewsBeforeLayout {
            view.clearPointerHighlight()
        }

        menu.update()

        for view in persistentMenuActionViews() {
            view.reconcilePointerHighlightWithCurrentLocation()
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            for view in self.persistentMenuActionViews() {
                view.reconcilePointerHighlightWithCurrentLocation()
            }
        }
    }

    private func refreshDeviceSectionEmptyStates() {
        inputEmptyMenuItem?.isHidden = inputDeviceMenuEntries.contains {
            !$0.item.isHidden
        }
        outputEmptyMenuItem?.isHidden = outputDeviceMenuEntries.contains {
            !$0.item.isHidden
        }
    }

    private func addOutputVolumeControl(for currentOutput: AudioDevice?) {
        let volumeItem = NSMenuItem()
        let volumeView = OutputVolumeMenuView(
            frame: NSRect(
                x: 0,
                y: 0,
                width: Self.menuContentWidth,
                height: 58
            )
        )
        outputVolumeControlDevice = currentOutput
        volumeView.onVolumeChange = { [weak self] volume, shouldUnmute in
            self?.setCurrentOutputVolume(
                volume,
                shouldUnmute: shouldUnmute
            )
        }
        volumeView.onTrackingChange = { [weak self] isTracking in
            self?.setOutputVolumeTracking(isTracking)
        }
        volumeView.onToggleMute = { [weak self] in
            self?.toggleCurrentOutputMute()
        }
        volumeView.configure(
            deviceName: currentOutput?.name,
            state: currentOutput.flatMap {
                audioDevices.outputVolumeState(for: $0)
            }
        )
        volumeItem.view = volumeView
        menu.addItem(volumeItem)
        outputVolumeView = volumeView
    }

    private func addApplicationVolumeSection() {
        let mode = applicationVolumeControlMode
        let headerItem = NSMenuItem()
        let headerView = ApplicationVolumeHeaderView(
            frame: NSRect(
                x: 0,
                y: 0,
                width: Self.menuContentWidth,
                height: 36
            )
        )
        headerView.configure(mode: mode)
        headerView.onModeChange = { [weak self] selectedMode in
            self?.setApplicationVolumeControlMode(selectedMode)
        }
        headerItem.view = headerView
        headerItem.toolTip = headerView.toolTip
        menu.addItem(headerItem)
        applicationVolumeHeaderView = headerView

        switch applicationVolumes.supportState {
        case .unsupported:
            let unavailableItem = NSMenuItem(
                title: "需要 macOS 15 或更高版本",
                action: nil,
                keyEquivalent: ""
            )
            unavailableItem.isEnabled = false
            addApplicationVolumeDetailItem(unavailableItem)
            return
        case .needsPermission:
            let retryPermissionItem = NSMenuItem(
                title: "重新请求应用音量权限",
                action: #selector(requestApplicationAudioPermission),
                keyEquivalent: ""
            )
            retryPermissionItem.target = self
            retryPermissionItem.toolTip = "macOS 将询问是否允许本机实时处理其他应用的声音"
            addApplicationVolumeDetailItem(retryPermissionItem)

            let settingsItem = NSMenuItem(
                title: "打开系统音频权限设置…",
                action: #selector(openApplicationAudioPrivacySettings),
                keyEquivalent: ""
            )
            settingsItem.target = self
            addApplicationVolumeDetailItem(settingsItem)
        case .failed(let message):
            let errorItem = NSMenuItem(
                title: "应用音量暂不可用",
                action: nil,
                keyEquivalent: ""
            )
            errorItem.isEnabled = false
            errorItem.toolTip = message
            addApplicationVolumeDetailItem(errorItem)
        case .ready:
            break
        }

        guard !applicationVolumes.applications.isEmpty else {
            let emptyItem = NSMenuItem(
                title: "当前没有可单独控制的应用",
                action: nil,
                keyEquivalent: ""
            )
            emptyItem.isEnabled = false
            addApplicationVolumeDetailItem(emptyItem)
            return
        }

        for application in applicationVolumes.applications {
            let item = NSMenuItem()
            let volumeView = ApplicationVolumeMenuView(
                frame: NSRect(
                    x: 0,
                    y: 0,
                    width: Self.menuContentWidth,
                    height: Self.applicationVolumeRowHeight
                )
            )
            volumeView.configure(application: application)
            volumeView.onVolumeChange = { [weak self] applicationID, volume in
                self?.applicationVolumes.setVolume(
                    volume,
                    forApplicationID: applicationID
                )
            }
            item.view = volumeView
            addApplicationVolumeDetailItem(item)
        }
    }

    private func addApplicationVolumeDetailItem(_ item: NSMenuItem) {
        item.isHidden = applicationVolumeControlMode == .unified
        menu.addItem(item)
        applicationVolumeDetailItems.append(item)
    }

    private func setApplicationVolumeControlMode(
        _ mode: ApplicationVolumeControlMode
    ) {
        guard applicationVolumeControlMode != mode else { return }

        applicationVolumeControlMode = mode
        applicationVolumeHeaderView?.configure(mode: mode)
        let shouldHideDetails = mode == .unified
        for item in applicationVolumeDetailItems {
            item.isHidden = shouldHideDetails
        }
        applicationVolumes.setIndividualControlEnabled(mode == .separate)
        updateMenuLayoutAndPointerHighlights()
        refreshMainWindowPresentation()
    }

    private func handleApplicationVolumeChange() {
        let nextState = applicationVolumes.supportState
        defer {
            lastApplicationVolumeSupportState = nextState
            if !isMainApplicationVolumeTracking {
                updatePresentation()
            }
        }

        guard applicationVolumeControlMode == .separate else { return }
        guard lastApplicationVolumeSupportState != nextState else { return }

        switch nextState {
        case .needsPermission:
            showTransientMessage(
                "应用音量需要“系统音频录制”权限",
                duration: 7
            )
        case .failed(let message):
            showTransientMessage("应用音量不可用：\(message)", duration: 6)
        case .ready:
            if lastApplicationVolumeSupportState == .needsPermission {
                showTransientMessage("应用音量控制已就绪", duration: 3)
            }
        case .unsupported:
            break
        }
    }

    private func setMainApplicationVolumeTracking(_ isTracking: Bool) {
        guard isMainApplicationVolumeTracking != isTracking else { return }
        isMainApplicationVolumeTracking = isTracking
        if !isTracking {
            updatePresentation()
        }
    }

    @discardableResult
    private func refreshOutputVolumeView(force: Bool = false) -> Bool {
        if force {
            outputVolumeReadbackWorkItem?.cancel()
            outputVolumeReadbackWorkItem = nil
            outputVolumeInteraction.completeAuthoritativeRefresh()
        } else if !outputVolumeInteraction.shouldApplySystemRefresh() {
            return false
        }

        let currentOutput = audioDevices.defaultOutputDevice()
        outputVolumeControlDevice = currentOutput
        outputVolumeView?.configure(
            deviceName: currentOutput?.name,
            state: currentOutput.flatMap {
                audioDevices.outputVolumeState(for: $0)
            }
        )
        return true
    }

    private func setCurrentOutputVolume(
        _ volume: Float,
        shouldUnmute: Bool
    ) {
        guard let currentOutput = outputVolumeControlDevice else {
            outputVolumeView?.showError("没有可用的系统输出")
            return
        }

        outputVolumeInteraction.noteLocalWrite()
        do {
            try audioDevices.setOutputVolume(
                volume,
                for: currentOutput,
                unmuteIfNeeded: shouldUnmute
            )
            if !outputVolumeInteraction.isTracking {
                scheduleOutputVolumeReadback()
            }
        } catch {
            outputVolumeView?.showError(error.localizedDescription)
            showTransientMessage("音量调节失败：\(error.localizedDescription)", duration: 4)
            refreshOutputVolumeView(force: true)
        }
    }

    private func setOutputVolumeTracking(_ isTracking: Bool) {
        outputVolumeReadbackWorkItem?.cancel()
        outputVolumeReadbackWorkItem = nil

        if isTracking {
            outputVolumeInteraction.beginTracking()
        } else {
            outputVolumeInteraction.endTracking()
            scheduleOutputVolumeReadback()
        }
    }

    private func scheduleOutputVolumeReadback() {
        outputVolumeReadbackWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.outputVolumeReadbackWorkItem = nil
            self.refreshOutputVolumeView(force: true)
            self.refreshMainWindowPresentation()
        }
        outputVolumeReadbackWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 0.04,
            execute: workItem
        )
    }

    private func toggleCurrentOutputMute() {
        guard let currentOutput = audioDevices.defaultOutputDevice(),
              let volumeState = audioDevices.outputVolumeState(for: currentOutput) else {
            outputVolumeView?.showError("当前输出不支持系统静音")
            return
        }

        do {
            try audioDevices.setOutputMuted(!volumeState.isMuted, for: currentOutput)
            refreshOutputVolumeView(force: true)
        } catch {
            outputVolumeView?.showError(error.localizedDescription)
            showTransientMessage("静音切换失败：\(error.localizedDescription)", duration: 4)
        }
    }

    private func synchronizeWithSystemInput(forceRestart: Bool) {
        guard !isSleeping else { return }
        ensureAudioMonitoring()
        retryWorkItem?.cancel()
        retryWorkItem = nil
        systemSyncWorkItem?.cancel()
        systemSyncWorkItem = nil

        guard let currentDevice = audioDevices.defaultInputDevice() else {
            cancelMicrophoneTest(
                message: "没有可用的麦克风",
                deviceUID: nil
            )
            keeperRequestedUID = nil
            lastSynchronizedSystemUID = nil
            retryAttempt = 0
            keeper.stop()
            showTransientMessage("没有找到可用的系统输入设备", duration: 4)
            return
        }

        if lastSynchronizedSystemUID != currentDevice.uid {
            retryAttempt = 0
            lastSynchronizedSystemUID = currentDevice.uid
        }

        if microphoneTestState.isActive,
           microphoneTestState.deviceUID != currentDevice.uid {
            cancelMicrophoneTest(
                message: "输入已切换，请重新测试",
                deviceUID: currentDevice.uid
            )
        }

        let shouldCapture = microphoneKeepAliveEnabled || microphoneTestState.isActive
        if shouldCapture {
            let alreadyActiveForCurrent: Bool
            switch keeperState {
            case .waitingForPermission:
                alreadyActiveForCurrent = keeperRequestedUID == currentDevice.uid
            case .starting(let deviceID, _),
                 .running(let deviceID, _),
                 .interrupted(let deviceID, _):
                alreadyActiveForCurrent =
                    keeperRequestedUID == currentDevice.uid &&
                    deviceID == currentDevice.uid
            case .permissionDenied:
                alreadyActiveForCurrent = keeperRequestedUID == currentDevice.uid
            case .stopped, .failed:
                alreadyActiveForCurrent = false
            }

            if forceRestart || !alreadyActiveForCurrent {
                keeperRequestedUID = currentDevice.uid
                keeper.start(preferredDeviceID: currentDevice.uid)
            }
        } else {
            keeperRequestedUID = nil
            keeper.stop()
        }

        updatePresentation()
    }

    private func ensureAudioMonitoring() {
        monitoringRetryWorkItem?.cancel()
        monitoringRetryWorkItem = nil

        if audioDevices.startMonitoring() {
            monitoringRetryAttempt = 0
            return
        }

        guard monitoringRetryAttempt < 5, !isSleeping else { return }
        let delay = min(pow(2.0, Double(monitoringRetryAttempt)), 16.0)
        monitoringRetryAttempt += 1

        let workItem = DispatchWorkItem { [weak self] in
            self?.ensureAudioMonitoring()
        }
        monitoringRetryWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func scheduleSystemSync(after delay: TimeInterval, forceRestart: Bool) {
        guard !isSleeping else { return }
        systemSyncWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.synchronizeWithSystemInput(forceRestart: forceRestart)
        }
        systemSyncWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func scheduleRetry() {
        guard !isSleeping,
              microphoneKeepAliveEnabled,
              audioDevices.defaultInputDevice() != nil else { return }

        retryWorkItem?.cancel()
        let delay = min(pow(2.0, Double(retryAttempt)), 30.0)
        retryAttempt += 1

        let workItem = DispatchWorkItem { [weak self] in
            self?.synchronizeWithSystemInput(forceRestart: true)
        }
        retryWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    @objc private func openMicrophoneTestInMainWindow() {
        presentMainWindow(destination: .inputTest)
    }

    private func startMicrophoneTest() {
        if microphoneTestState.isActive {
            refreshMainWindowPresentation()
            return
        }

        guard let currentInput = audioDevices.defaultInputDevice() else {
            microphoneTestState = .failed(
                deviceUID: nil,
                message: "没有可用的麦克风"
            )
            refreshMainWindowPresentation()
            return
        }

        microphoneTestState = .preparing(deviceUID: currentInput.uid)
        keeper.setLevelMonitoringEnabled(true)
        refreshMainWindowPresentation()

        if keeperIsRunning(for: currentInput.uid) {
            beginMicrophoneTestMeasurement(deviceUID: currentInput.uid)
        } else {
            synchronizeWithSystemInput(forceRestart: true)
        }
    }

    private func beginMicrophoneTestMeasurement(deviceUID: String) {
        guard case .preparing(let requestedUID) = microphoneTestState,
              requestedUID == deviceUID else { return }

        microphoneTestState = .testing(deviceUID: deviceUID)
        refreshMainWindowPresentation()
        updatePresentation()
    }

    private func applyMicrophoneTestLevel(_ level: MicrophoneAudioLevel) {
        if case .preparing(let deviceUID) = microphoneTestState {
            beginMicrophoneTestMeasurement(deviceUID: deviceUID)
        }
        guard case .testing = microphoneTestState else { return }

        mainWindowController?.pushMicrophoneLevel(level)
    }

    private func stopMicrophoneTest() {
        let wasActive = microphoneTestState.isActive
        let wasFailed: Bool
        if case .failed = microphoneTestState {
            wasFailed = true
        } else {
            wasFailed = false
        }
        guard wasActive || wasFailed else { return }

        keeper.setLevelMonitoringEnabled(false)
        microphoneTestState = .idle
        refreshMainWindowPresentation()

        if wasActive, !microphoneKeepAliveEnabled {
            synchronizeWithSystemInput(forceRestart: false)
        } else {
            updatePresentation()
        }
    }

    private func cancelMicrophoneTest(message: String, deviceUID: String?) {
        guard microphoneTestState.isActive else { return }

        keeper.setLevelMonitoringEnabled(false)
        microphoneTestState = .failed(deviceUID: deviceUID, message: message)
        refreshMainWindowPresentation()
    }

    private func keeperIsRunning(for deviceUID: String) -> Bool {
        guard keeperRequestedUID == deviceUID else { return false }
        if case .running(let activeDeviceUID, _) = keeperState {
            return activeDeviceUID == deviceUID
        }
        return false
    }

    private func apply(keeperState newState: MicKeeper.State) {
        keeperState = newState

        switch newState {
        case .running(let deviceUID, _):
            retryWorkItem?.cancel()
            retryWorkItem = nil
            retryAttempt = 0
            beginMicrophoneTestMeasurement(deviceUID: deviceUID)
        case .failed(let message):
            cancelMicrophoneTest(
                message: "测试失败：\(message)",
                deviceUID: audioDevices.defaultInputDevice()?.uid
            )
            scheduleRetry()
        case .permissionDenied:
            retryWorkItem?.cancel()
            retryWorkItem = nil
            cancelMicrophoneTest(
                message: "没有麦克风权限",
                deviceUID: audioDevices.defaultInputDevice()?.uid
            )
        case .interrupted:
            let wasTesting = microphoneTestState.isActive
            cancelMicrophoneTest(
                message: "麦克风输入已中断",
                deviceUID: audioDevices.defaultInputDevice()?.uid
            )
            if wasTesting, !microphoneKeepAliveEnabled {
                keeperRequestedUID = nil
                keeper.stop()
            }
        case .stopped:
            cancelMicrophoneTest(
                message: "麦克风输入已停止",
                deviceUID: audioDevices.defaultInputDevice()?.uid
            )
        case .waitingForPermission, .starting:
            break
        }

        updatePresentation()
    }

    private func updatePresentation() {
        guard statusItem != nil else { return }
        let currentInput = audioDevices.defaultInputDevice()
        let currentOutput = audioDevices.defaultOutputDevice()
        let text = statusText(for: currentInput)
        let iconName: String
        let usesCustomStatusBarIcon: Bool

        if transientMessage != nil {
            iconName = "exclamationmark.triangle"
            usesCustomStatusBarIcon = false
        } else if microphoneTestState.isActive {
            iconName = "waveform"
            usesCustomStatusBarIcon = false
        } else if !microphoneKeepAliveEnabled {
            iconName = "mic"
            usesCustomStatusBarIcon = true
        } else {
            switch keeperState {
            case .running:
                iconName = "mic.fill"
                usesCustomStatusBarIcon = true
            case .waitingForPermission, .starting, .interrupted:
                iconName = "mic.badge.plus"
                usesCustomStatusBarIcon = true
            case .stopped:
                iconName = "mic"
                usesCustomStatusBarIcon = true
            case .permissionDenied:
                iconName = "mic.slash.fill"
                usesCustomStatusBarIcon = false
            case .failed:
                iconName = "exclamationmark.triangle"
                usesCustomStatusBarIcon = false
            }
        }

        statusItem.button?.image = statusBarImage(
            fallbackSystemSymbolName: iconName,
            usesCustomArtwork: usesCustomStatusBarIcon
        )
        statusItem.button?.imageScaling = .scaleProportionallyDown
        statusItem.button?.toolTip = "当前输入：\(currentInput?.name ?? "未找到")；当前输出：\(currentOutput?.name ?? "未找到")；\(text)"
        statusItem.button?.setAccessibilityLabel(
            "音频快捷切换。当前输入 \(currentInput?.name ?? "未找到")。当前输出 \(currentOutput?.name ?? "未找到")。\(text)"
        )
        refreshPersistentMenuPresentation()
        refreshMainWindowPresentation()
    }

    private func statusText(for currentDevice: AudioDevice?) -> String {
        if let transientMessage {
            return transientMessage
        }
        guard let currentDevice else {
            return "没有可用的系统输入"
        }

        switch microphoneTestState {
        case .preparing:
            return "正在准备实时麦克风测试…"
        case .testing:
            return "正在实时测试麦克风 · 请说话"
        case .idle, .failed:
            break
        }

        guard microphoneKeepAliveEnabled else {
            return "已切换 · 麦克风常驻已关闭"
        }

        switch keeperState {
        case .waitingForPermission:
            return "系统已切换 · 等待麦克风权限"
        case .starting(let deviceID, let deviceName):
            guard deviceID == currentDevice.uid,
                  keeperRequestedUID == currentDevice.uid else {
                return "正在让 \(currentDevice.name) 进入待命状态…"
            }
            return "正在让 \(deviceName) 进入待命状态…"
        case .running(let deviceID, let deviceName):
            guard deviceID == currentDevice.uid,
                  keeperRequestedUID == currentDevice.uid else {
                return "正在让 \(currentDevice.name) 进入待命状态…"
            }
            return "已就绪 · \(deviceName) 保持在线"
        case .interrupted(let deviceID, _):
            guard deviceID == currentDevice.uid,
                  keeperRequestedUID == currentDevice.uid else {
                return "正在让 \(currentDevice.name) 进入待命状态…"
            }
            return "输入暂时中断 · 等待恢复"
        case .stopped:
            return "系统已切换 · 正在打开输入通道…"
        case .permissionDenied:
            return "系统已切换 · 没有权限保持在线"
        case .failed(let message):
            return "系统已切换 · 保持在线失败：\(message)"
        }
    }

    private func showTransientMessage(_ message: String, duration: TimeInterval) {
        transientMessageToken += 1
        let token = transientMessageToken
        transientMessage = message
        updatePresentation()

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self, self.transientMessageToken == token else { return }
            self.transientMessage = nil
            self.updatePresentation()
        }
    }

    private func launchAtLoginToolTip() -> String {
        if SMAppService.mainApp.status == .enabled {
            return "已开启；点击后关闭开机自动启动"
        }
        if SMAppService.mainApp.status == .requiresApproval {
            return "需要在系统设置的登录项中批准；点击打开设置"
        }
        return "登录 macOS 后自动启动 MacSoundControl"
    }

    private func selectSystemDevice(
        direction: PersistentDeviceMenuDirection,
        uid: String
    ) {
        switch direction {
        case .input:
            selectSystemInput(uid: uid)
        case .output:
            selectSystemOutput(uid: uid)
        }
    }

    private func selectSystemInput(uid targetUID: String) {
        guard let target = audioDevices.inputDevices().first(where: {
            $0.uid == targetUID
        }) else {
            showTransientMessage("这个麦克风已经断开", duration: 4)
            return
        }

        let oldDefaultUID = audioDevices.defaultInputDevice()?.uid
        do {
            try audioDevices.setDefaultInputDevice(uid: target.uid)
            guard audioDevices.defaultInputDevice()?.uid == target.uid else {
                showTransientMessage("系统没有完成输入切换", duration: 4)
                return
            }

            retryAttempt = 0
            if oldDefaultUID == target.uid {
                synchronizeWithSystemInput(forceRestart: false)
            } else {
                cancelMicrophoneTest(
                    message: "输入已切换，请重新测试",
                    deviceUID: target.uid
                )
                synchronizeWithSystemInput(forceRestart: true)
            }
        } catch {
            showTransientMessage(
                "切换失败，仍在使用 \(audioDevices.defaultInputDevice()?.name ?? "原麦克风")：\(error.localizedDescription)",
                duration: 5
            )
        }
    }

    private func selectSystemOutput(uid targetUID: String) {
        guard !isOutputSelectionInFlight else { return }
        guard let target = audioDevices.outputDevices().first(where: {
            $0.uid == targetUID
        }) else {
            showTransientMessage("这个输出设备已经断开", duration: 4)
            return
        }

        if audioDevices.defaultOutputDevice()?.uid == target.uid {
            updatePresentation()
            return
        }

        isOutputSelectionInFlight = true
        updatePresentation()
        applicationVolumes.prepareForOutputSwitch { [weak self] isReady in
            guard let self else { return }
            guard isReady else {
                self.isOutputSelectionInFlight = false
                self.showTransientMessage(
                    "应用音量通道尚未释放，暂未切换系统输出",
                    duration: 5
                )
                return
            }

            do {
                try self.audioDevices.setDefaultOutputDevice(uid: target.uid)
                let actualOutput = self.audioDevices.defaultOutputDevice()
                self.applicationVolumes.completeOutputSwitch(
                    outputDeviceUID: actualOutput?.uid
                )
                self.isOutputSelectionInFlight = false
                self.refreshOutputVolumeView()

                guard actualOutput?.uid == target.uid else {
                    self.showTransientMessage("系统没有完成输出切换", duration: 4)
                    return
                }
                self.updatePresentation()
            } catch {
                let actualOutput = self.audioDevices.defaultOutputDevice()
                self.applicationVolumes.completeOutputSwitch(
                    outputDeviceUID: actualOutput?.uid
                )
                self.isOutputSelectionInFlight = false
                self.refreshOutputVolumeView()
                self.showTransientMessage(
                    "切换失败，仍在使用 \(actualOutput?.name ?? "原输出设备")：\(error.localizedDescription)",
                    duration: 5
                )
            }
        }
    }

    private func toggleMicrophoneKeepAlive() {
        microphoneKeepAliveEnabled.toggle()
        retryAttempt = 0
        let shouldRestart = microphoneKeepAliveEnabled && !microphoneTestState.isActive
        synchronizeWithSystemInput(forceRestart: shouldRestart)
    }

    private func toggleShowVirtualDevices() {
        showVirtualDevices.toggle()
        updateVirtualDeviceVisibility()
        updatePresentation()
    }

    @objc private func openMainWindow() {
        presentMainWindow(destination: .outputVolume)
    }

    private func presentMainWindow(destination: MainWindowDestination) {
        let snapshot = makeMainWindowSnapshot()
        if let mainWindowController {
            mainWindowController.update(snapshot: snapshot)
            mainWindowController.present(destination: destination)
            return
        }

        let controller = MainWindowController(
            snapshot: snapshot,
            actions: makeMainWindowActions()
        )
        mainWindowController = controller
        controller.present(destination: destination)
    }

    private func makeMainWindowActions() -> MainWindowActions {
        MainWindowActions(
            showMenu: { [weak self] in
                self?.statusItem.button?.performClick(nil)
            },
            selectInput: { [weak self] uid in
                self?.selectSystemInput(uid: uid)
            },
            selectOutput: { [weak self] uid in
                self?.selectSystemOutput(uid: uid)
            },
            setOutputVolume: { [weak self] volume, shouldUnmute in
                self?.setCurrentOutputVolume(
                    volume,
                    shouldUnmute: shouldUnmute
                )
            },
            setOutputVolumeTracking: { [weak self] isTracking in
                self?.setOutputVolumeTracking(isTracking)
            },
            toggleOutputMute: { [weak self] in
                self?.toggleCurrentOutputMute()
            },
            setApplicationVolumeMode: { [weak self] mode in
                self?.setApplicationVolumeControlMode(mode)
            },
            setApplicationVolume: { [weak self] applicationID, volume in
                self?.applicationVolumes.setVolume(
                    volume,
                    forApplicationID: applicationID
                )
            },
            setApplicationVolumeTracking: { [weak self] isTracking in
                self?.setMainApplicationVolumeTracking(isTracking)
            },
            toggleKeepAlive: { [weak self] in
                self?.toggleMicrophoneKeepAlive()
            },
            toggleVirtualDevices: { [weak self] in
                self?.toggleShowVirtualDevices()
            },
            toggleLaunchAtLogin: { [weak self] in
                self?.toggleLaunchAtLogin()
            },
            reconnectInput: { [weak self] in
                self?.reconnectCurrentInput()
            },
            requestApplicationAudioPermission: { [weak self] in
                self?.requestApplicationAudioPermission()
            },
            openApplicationAudioPrivacySettings: { [weak self] in
                self?.openApplicationAudioPrivacySettings()
            },
            openMicrophonePrivacySettings: { [weak self] in
                self?.openMicrophonePrivacySettings()
            },
            startInputTest: { [weak self] in
                self?.startMicrophoneTest()
            },
            stopInputTest: { [weak self] in
                self?.stopMicrophoneTest()
            },
            openThirdPartyNotices: { [weak self] in
                self?.openThirdPartyNotices()
            },
            quitApplication: { [weak self] in
                self?.quit()
            }
        )
    }

    private func refreshMainWindowPresentation() {
        mainWindowController?.update(snapshot: makeMainWindowSnapshot())
    }

    private func makeMainWindowSnapshot() -> MainWindowSnapshot {
        let currentInput = audioDevices.defaultInputDevice()
        let currentOutput = audioDevices.defaultOutputDevice()
        outputVolumeControlDevice = currentOutput

        let visibleInputs = audioDevices.inputDevices().filter {
            showVirtualDevices || !$0.isVirtual
        }
        let visibleOutputs = audioDevices.outputDevices().filter {
            showVirtualDevices || !$0.isVirtual
        }

        let inputSnapshots = visibleInputs.map { device in
            MainWindowDeviceSnapshot(
                uid: device.uid,
                name: device.name,
                detail: device.menuDetail,
                symbolName: AudioDevicePresentation.symbolName(
                    deviceName: device.name,
                    transportType: device.transportType,
                    direction: .input
                ),
                isSelected: device.uid == currentInput?.uid
            )
        }
        let outputSnapshots = visibleOutputs.map { device in
            MainWindowDeviceSnapshot(
                uid: device.uid,
                name: device.name,
                detail: device.menuDetail,
                symbolName: AudioDevicePresentation.symbolName(
                    deviceName: device.name,
                    transportType: device.transportType,
                    direction: .output
                ),
                isSelected: device.uid == currentOutput?.uid
            )
        }

        let currentInputSnapshot = currentInput.map { device in
            MainWindowDeviceSnapshot(
                uid: device.uid,
                name: device.name,
                detail: device.menuDetail,
                symbolName: AudioDevicePresentation.symbolName(
                    deviceName: device.name,
                    transportType: device.transportType,
                    direction: .input
                ),
                isSelected: true
            )
        }

        let testPhase: MainWindowMicrophoneTestPhase
        let testMatchesCurrentInput = microphoneTestState.deviceUID == currentInput?.uid
        switch microphoneTestState {
        case .idle:
            testPhase = .idle
        case .preparing where testMatchesCurrentInput:
            testPhase = .preparing
        case .testing where testMatchesCurrentInput:
            testPhase = .testing
        case .failed(let deviceUID, let message)
            where deviceUID == nil || testMatchesCurrentInput:
            testPhase = .failed(message: message)
        case .preparing, .testing, .failed:
            testPhase = .idle
        }

        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "2.3"
        let build = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "30"

        return MainWindowSnapshot(
            inputDevices: inputSnapshots,
            outputDevices: outputSnapshots,
            outputVolume: MainWindowOutputVolumeSnapshot(
                deviceName: currentOutput?.name,
                state: currentOutput.flatMap {
                    audioDevices.outputVolumeState(for: $0)
                }
            ),
            applicationVolumeMode: applicationVolumeControlMode,
            applicationVolumeSupportState: applicationVolumes.supportState,
            applications: applicationVolumes.applications,
            keepAliveEnabled: microphoneKeepAliveEnabled,
            virtualDevicesVisible: showVirtualDevices,
            launchAtLoginEnabled: SMAppService.mainApp.status == .enabled,
            launchAtLoginRequiresApproval: SMAppService.mainApp.status == .requiresApproval,
            canReconnectInput: currentInput != nil && microphoneKeepAliveEnabled,
            microphonePermissionDenied: {
                if case .permissionDenied = keeperState { return true }
                return false
            }(),
            microphoneTest: MainWindowMicrophoneTestSnapshot(
                device: currentInputSnapshot,
                phase: testPhase
            ),
            statusMessage: transientMessage,
            versionText: "版本 \(version)（\(build)）"
        )
    }

    private func openThirdPartyNotices() {
        guard let noticesURL = Bundle.main.url(
            forResource: "THIRD_PARTY_NOTICES",
            withExtension: "md"
        ) else {
            showTransientMessage("未找到第三方许可说明", duration: 4)
            return
        }
        NSWorkspace.shared.open(noticesURL)
    }

    @objc private func requestApplicationAudioPermission() {
        applicationVolumes.requestSystemAudioPermission()
    }

    @objc private func openApplicationAudioPrivacySettings() {
        let privacyURLs = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.preference.security?Privacy",
        ]

        for privacyURL in privacyURLs {
            guard let url = URL(string: privacyURL),
                  NSWorkspace.shared.open(url) else {
                continue
            }
            return
        }
    }

    private func toggleLaunchAtLogin() {
        do {
            let service = SMAppService.mainApp
            if service.status == .enabled {
                try service.unregister()
            } else if service.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            } else {
                try service.register()
                if service.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                }
            }
            refreshPersistentMenuPresentation()
            updateMenuLayoutAndPointerHighlights()
            refreshMainWindowPresentation()
        } catch {
            showTransientMessage("无法修改开机自动启动：\(error.localizedDescription)", duration: 5)
        }
    }

    @objc private func reconnectCurrentInput() {
        retryAttempt = 0
        synchronizeWithSystemInput(forceRestart: true)
    }

    @objc private func openMicrophonePrivacySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func symbol(named name: String) -> NSImage? {
        let image = NSImage(
            systemSymbolName: name,
            accessibilityDescription: "麦克风快捷切换"
        )
        image?.isTemplate = true
        return image
    }

    private func statusBarImage(
        fallbackSystemSymbolName: String,
        usesCustomArtwork: Bool
    ) -> NSImage? {
        if usesCustomArtwork, let customStatusBarIcon {
            return customStatusBarIcon
        }
        return symbol(named: fallbackSystemSymbolName)
    }
}

#if INTERFACE_VISUAL_PROBE
try InterfaceVisualProbe.main()
#else
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
#endif
