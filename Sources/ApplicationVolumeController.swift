import AppKit
import AudioToolbox
import CoreAudio
import Darwin
import Foundation

struct OutputAudioApplication: Equatable {
    let id: String
    let bundleID: String
    let name: String
    let bundleURL: URL?
    let icon: NSImage?
    let audioObjectIDs: [AudioObjectID]
    var volume: Double

    static func == (
        lhs: OutputAudioApplication,
        rhs: OutputAudioApplication
    ) -> Bool {
        lhs.id == rhs.id
            && lhs.bundleID == rhs.bundleID
            && lhs.name == rhs.name
            && lhs.bundleURL == rhs.bundleURL
            && lhs.audioObjectIDs == rhs.audioObjectIDs
            && lhs.volume == rhs.volume
    }
}

enum ApplicationVolumeSupportState: Equatable {
    case unsupported
    case ready
    case needsPermission
    case failed(message: String)
}

protocol ApplicationVolumeControlling: AnyObject {
    var applications: [OutputAudioApplication] { get }
    var supportState: ApplicationVolumeSupportState { get }
    var onChange: (() -> Void)? { get set }

    func start(outputDeviceUID: String?)
    func stop()
    func refresh()
    func setIndividualControlEnabled(_ enabled: Bool)
    func setVolume(_ volume: Double, forApplicationID applicationID: String)
    func requestSystemAudioPermission()
    func prepareForOutputSwitch(completion: @escaping (Bool) -> Void)
    func completeOutputSwitch(outputDeviceUID: String?)
    func handleExternalOutputRouteChange(outputDeviceUID: String?)
}

enum ApplicationVolumeControllerFactory {
    static func make() -> ApplicationVolumeControlling {
        if #available(macOS 15.0, *) {
            return ProcessTapApplicationVolumeController()
        }

        return UnsupportedApplicationVolumeController()
    }
}

private final class UnsupportedApplicationVolumeController: ApplicationVolumeControlling {
    let applications: [OutputAudioApplication] = []
    let supportState: ApplicationVolumeSupportState = .unsupported
    var onChange: (() -> Void)?

    func start(outputDeviceUID: String?) {}
    func stop() {}
    func refresh() {}
    func setIndividualControlEnabled(_ enabled: Bool) {}
    func setVolume(_ volume: Double, forApplicationID applicationID: String) {}
    func requestSystemAudioPermission() {}
    func completeOutputSwitch(outputDeviceUID: String?) {}
    func handleExternalOutputRouteChange(outputDeviceUID: String?) {}

    func prepareForOutputSwitch(completion: @escaping (Bool) -> Void) {
        completion(true)
    }
}

@available(macOS 15.0, *)
private final class ProcessTapApplicationVolumeController: ApplicationVolumeControlling, @unchecked Sendable {
    private static let volumeDefaultsPrefix = "applicationOutputVolume."
    private static let reconcileDelay: TimeInterval = 0.035
    private static let refreshDelay: TimeInterval = 0.12

    private let defaults = UserDefaults.standard
    private let hardware = ApplicationAudioHardware()
    private let monitor = ApplicationAudioProcessMonitor()
    private let mixer = AppAudioMixer.shared

    private(set) var applications: [OutputAudioApplication] = []
    private(set) var supportState: ApplicationVolumeSupportState = .ready
    var onChange: (() -> Void)?

    private var outputDeviceUID: String?
    private var routeGeneration: UInt64 = 0
    private var commandRevision: UInt64 = 0
    private var lastSubmittedSnapshot: AppMixerSnapshot?
    private var reconcileWorkItem: DispatchWorkItem?
    private var refreshWorkItem: DispatchWorkItem?
    private var isStarted = false
    private var isOutputSwitching = false
    private var isPermissionProbeInFlight = false
    private var hasConfirmedSystemAudioPermission = false
    private var isIndividualControlEnabled = true

    init() {
        monitor.onChange = { [weak self] in
            self?.scheduleRefresh()
        }
    }

    func start(outputDeviceUID: String?) {
        self.outputDeviceUID = outputDeviceUID
        guard !isStarted else {
            refresh()
            return
        }

        isStarted = true
        monitor.start()
        refresh()
    }

    func stop() {
        reconcileWorkItem?.cancel()
        reconcileWorkItem = nil
        refreshWorkItem?.cancel()
        refreshWorkItem = nil
        monitor.stop()
        isStarted = false
        isOutputSwitching = false
        lastSubmittedSnapshot = nil
        commandRevision &+= 1
        mixer.noteLatestCommand(revision: commandRevision)
        mixer.stopAll()
    }

    func refresh() {
        guard isStarted else { return }

        let nextApplications = hardware.controllableApplications { [weak self] bundleID in
            self?.storedVolume(for: bundleID) ?? 1
        }

        if nextApplications != applications {
            applications = nextApplications
            onChange?()
        }

        scheduleReconcile(requestAuthorizationIfDenied: false)
    }

    func setIndividualControlEnabled(_ enabled: Bool) {
        guard isIndividualControlEnabled != enabled else { return }
        isIndividualControlEnabled = enabled

        reconcileWorkItem?.cancel()
        reconcileWorkItem = nil
        lastSubmittedSnapshot = nil

        guard isStarted, !isOutputSwitching else { return }
        commandRevision &+= 1
        mixer.noteLatestCommand(revision: commandRevision)

        let needsAuthorization = enabled && currentTargets().contains {
            abs($0.volume - 1) >= 0.005
        }
        scheduleReconcile(requestAuthorizationIfDenied: needsAuthorization)
    }

    func setVolume(_ volume: Double, forApplicationID applicationID: String) {
        guard isIndividualControlEnabled else { return }
        guard let index = applications.firstIndex(where: { $0.id == applicationID }) else {
            return
        }

        let clampedVolume = max(0, min(1, volume))
        guard abs(applications[index].volume - clampedVolume) >= 0.001 else {
            return
        }

        applications[index].volume = clampedVolume
        defaults.set(
            clampedVolume,
            forKey: Self.volumeDefaultsPrefix + applications[index].bundleID
        )
        onChange?()
        scheduleReconcile(
            requestAuthorizationIfDenied: abs(clampedVolume - 1) >= 0.005
        )
    }

    func requestSystemAudioPermission() {
        guard isIndividualControlEnabled else { return }
        guard !isPermissionProbeInFlight else { return }
        isPermissionProbeInFlight = true

        mixer.probeSystemAudioPermission { [weak self] isAvailable in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isPermissionProbeInFlight = false
                if !self.isIndividualControlEnabled {
                    self.setSupportState(.ready)
                    self.lastSubmittedSnapshot = nil
                    self.scheduleReconcile(requestAuthorizationIfDenied: false)
                } else if isAvailable {
                    self.hasConfirmedSystemAudioPermission = true
                    self.setSupportState(.ready)
                    self.lastSubmittedSnapshot = nil
                    self.scheduleReconcile(requestAuthorizationIfDenied: false)
                } else {
                    self.hasConfirmedSystemAudioPermission = false
                    self.setSupportState(.needsPermission)
                }
            }
        }
    }

    func prepareForOutputSwitch(completion: @escaping (Bool) -> Void) {
        reconcileWorkItem?.cancel()
        reconcileWorkItem = nil
        isOutputSwitching = true
        commandRevision &+= 1
        let revision = commandRevision
        mixer.noteLatestCommand(revision: revision)

        mixer.submitQuiesceForOutputSwitch(
            revision: revision,
            targets: currentTargets()
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.commandRevision == revision else {
                    completion(false)
                    return
                }

                guard result == .applied else {
                    self.isOutputSwitching = false
                    self.mixer.cancelOutputSwitch(revision: revision)
                    self.lastSubmittedSnapshot = nil
                    self.scheduleReconcile(requestAuthorizationIfDenied: false)
                    completion(false)
                    return
                }

                completion(true)
            }
        }
    }

    func completeOutputSwitch(outputDeviceUID: String?) {
        self.outputDeviceUID = outputDeviceUID
        routeGeneration &+= 1
        lastSubmittedSnapshot = nil

        guard let outputDeviceUID else {
            isOutputSwitching = false
            commandRevision &+= 1
            mixer.noteLatestCommand(revision: commandRevision)
            mixer.stopAll()
            setSupportState(.ready)
            return
        }

        commandRevision &+= 1
        let command = makeCommand(outputDeviceUID: outputDeviceUID)
        lastSubmittedSnapshot = command.snapshot
        mixer.noteLatestCommand(revision: command.revision)
        mixer.submitTransitionCompletingOutputSwitch(command) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.commandRevision == command.revision else { return }
                self.isOutputSwitching = false
                self.handleMixerResult(
                    result,
                    command: command,
                    requestAuthorizationIfDenied: false
                )
            }
        }
    }

    func handleExternalOutputRouteChange(outputDeviceUID: String?) {
        guard self.outputDeviceUID != outputDeviceUID else { return }
        self.outputDeviceUID = outputDeviceUID
        routeGeneration &+= 1
        lastSubmittedSnapshot = nil

        guard !isOutputSwitching else { return }

        guard let outputDeviceUID else {
            commandRevision &+= 1
            mixer.noteLatestCommand(revision: commandRevision)
            mixer.stopAll()
            return
        }

        commandRevision &+= 1
        let command = makeCommand(outputDeviceUID: outputDeviceUID)
        lastSubmittedSnapshot = command.snapshot
        mixer.noteLatestCommand(revision: command.revision)
        mixer.submitTransition(command) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.commandRevision == command.revision else { return }
                self.handleMixerResult(
                    result,
                    command: command,
                    requestAuthorizationIfDenied: false
                )
            }
        }
    }

    private func scheduleRefresh() {
        refreshWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.refresh()
        }
        refreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.refreshDelay,
            execute: workItem
        )
    }

    private func scheduleReconcile(requestAuthorizationIfDenied: Bool) {
        guard isStarted, !isOutputSwitching else { return }

        reconcileWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.submitReconcile(
                requestAuthorizationIfDenied: requestAuthorizationIfDenied
            )
        }
        reconcileWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.reconcileDelay,
            execute: workItem
        )
    }

    private func submitReconcile(requestAuthorizationIfDenied: Bool) {
        guard isStarted, !isOutputSwitching else { return }

        let snapshot = AppMixerSnapshot(
            routeGeneration: routeGeneration,
            outputDeviceUID: outputDeviceUID,
            targets: outputDeviceUID == nil ? [] : currentTargets()
        )
        guard snapshot != lastSubmittedSnapshot else { return }

        commandRevision &+= 1
        let command = AppMixerCommand(
            revision: commandRevision,
            routeGeneration: snapshot.routeGeneration,
            outputDeviceUID: snapshot.outputDeviceUID,
            targets: snapshot.targets
        )
        lastSubmittedSnapshot = snapshot
        mixer.noteLatestCommand(revision: command.revision)
        mixer.submitReconcile(command) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.commandRevision == command.revision else { return }
                self.handleMixerResult(
                    result,
                    command: command,
                    requestAuthorizationIfDenied: requestAuthorizationIfDenied
                )
            }
        }
    }

    private func handleMixerResult(
        _ result: AppMixerResult,
        command: AppMixerCommand,
        requestAuthorizationIfDenied: Bool
    ) {
        guard commandRevision == command.revision,
              routeGeneration == command.routeGeneration else {
            return
        }

        switch result {
        case .applied:
            if command.targets.contains(where: { abs($0.volume - 1) >= 0.005 }) {
                hasConfirmedSystemAudioPermission = true
            }
            setSupportState(.ready)
        case .superseded:
            break
        case .failed:
            lastSubmittedSnapshot = nil
            let requiresPermission = command.targets.contains {
                abs($0.volume - 1) >= 0.005
            }
            if requiresPermission {
                if hasConfirmedSystemAudioPermission {
                    setSupportState(
                        .failed(message: "当前输出无法创建应用音量通道")
                    )
                } else {
                    setSupportState(.needsPermission)
                }
                if requestAuthorizationIfDenied,
                   !hasConfirmedSystemAudioPermission {
                    requestSystemAudioPermission()
                }
            } else {
                setSupportState(.failed(message: "当前输出暂时无法创建应用音量通道"))
            }
        }
    }

    private func currentTargets() -> [AppMixTarget] {
        return applications
            .map {
                AppMixTarget(
                    id: $0.id,
                    audioObjectIDs: $0.audioObjectIDs,
                    volume: ApplicationVolumeTargetPolicy.effectiveVolume(
                        savedVolume: $0.volume,
                        individualControlEnabled: isIndividualControlEnabled
                    )
                )
            }
            .sorted { $0.id < $1.id }
    }

    private func makeCommand(outputDeviceUID: String) -> AppMixerCommand {
        AppMixerCommand(
            revision: commandRevision,
            routeGeneration: routeGeneration,
            outputDeviceUID: outputDeviceUID,
            targets: currentTargets()
        )
    }

    private func setSupportState(_ state: ApplicationVolumeSupportState) {
        guard supportState != state else { return }
        supportState = state
        onChange?()
    }

    private func storedVolume(for bundleID: String) -> Double {
        let key = Self.volumeDefaultsPrefix + bundleID
        guard defaults.object(forKey: key) != nil else { return 1 }
        return max(0, min(1, defaults.double(forKey: key)))
    }
}

@available(macOS 15.0, *)
private struct ApplicationAudioHardware {
    func controllableApplications(
        storedVolume: (String) -> Double
    ) -> [OutputAudioApplication] {
        struct GroupedApplication {
            let bundleID: String
            let name: String
            let bundleURL: URL?
            let icon: NSImage?
            var audioObjectIDs: [AudioObjectID]
        }

        var groupedApplications: [String: GroupedApplication] = [:]
        let currentPID = ProcessInfo.processInfo.processIdentifier

        for audioObjectID in audioObjectIDs(
            objectID: AudioObjectID(kAudioObjectSystemObject),
            selector: kAudioHardwarePropertyProcessObjectList
        ) {
            guard let pid = pidProperty(audioObjectID),
                  pid != currentPID else {
                continue
            }

            let audioBundleID = stringProperty(
                audioObjectID,
                selector: kAudioProcessPropertyBundleID
            )
            guard let application = responsibleApplication(
                for: pid,
                audioBundleID: audioBundleID
            ) else {
                continue
            }

            let bundleID = application.bundleIdentifier
                ?? audioBundleID
                ?? "pid.\(application.processIdentifier)"
            let stableID = bundleID.isEmpty
                ? "pid.\(application.processIdentifier)"
                : bundleID
            let name = application.localizedName ?? stableID

            if groupedApplications[stableID] == nil {
                groupedApplications[stableID] = GroupedApplication(
                    bundleID: stableID,
                    name: name,
                    bundleURL: application.bundleURL,
                    icon: application.icon,
                    audioObjectIDs: []
                )
            }
            groupedApplications[stableID]?.audioObjectIDs.append(audioObjectID)
        }

        return groupedApplications.map { id, application in
            OutputAudioApplication(
                id: id,
                bundleID: application.bundleID,
                name: application.name,
                bundleURL: application.bundleURL,
                icon: application.icon,
                audioObjectIDs: application.audioObjectIDs.sorted(),
                volume: storedVolume(application.bundleID)
            )
        }
        .sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private func responsibleApplication(
        for pid: pid_t,
        audioBundleID: String?
    ) -> NSRunningApplication? {
        var visited = Set<pid_t>()
        var candidatePID = pid

        while candidatePID > 0, !visited.contains(candidatePID) {
            visited.insert(candidatePID)
            if let application = NSRunningApplication(processIdentifier: candidatePID),
               application.activationPolicy == .regular {
                return application
            }

            guard let parentPID = parentProcessID(for: candidatePID),
                  parentPID != candidatePID else {
                break
            }
            candidatePID = parentPID
        }

        return inferredHostApplication(for: pid, audioBundleID: audioBundleID)
    }

    private func inferredHostApplication(
        for pid: pid_t,
        audioBundleID: String?
    ) -> NSRunningApplication? {
        let searchableText = [
            audioBundleID,
            processName(for: pid),
            processPath(for: pid),
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .lowercased()

        guard searchableText.contains("com.apple.safari")
                || searchableText.contains("safari.app")
                || searchableText.contains("safari web content")
                || searchableText.contains("com.apple.webkit")
                || searchableText.contains("webkit.webcontent") else {
            return nil
        }

        return NSWorkspace.shared.runningApplications.first {
            ["com.apple.Safari", "com.apple.SafariTechnologyPreview"]
                .contains($0.bundleIdentifier ?? "")
                && $0.activationPolicy == .regular
        }
    }

    private func audioObjectIDs(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> [AudioObjectID] {
        var address = propertyAddress(selector: selector)
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            objectID,
            &address,
            0,
            nil,
            &dataSize
        ) == noErr else {
            return []
        }

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else { return [] }

        var objectIDs = Array(
            repeating: AudioObjectID(kAudioObjectUnknown),
            count: count
        )
        let status = AudioObjectGetPropertyData(
            objectID,
            &address,
            0,
            nil,
            &dataSize,
            &objectIDs
        )
        return status == noErr
            ? objectIDs.filter { $0 != kAudioObjectUnknown }
            : []
    }

    private func stringProperty(
        _ objectID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> String? {
        var address = propertyAddress(selector: selector)
        var value: CFString?
        var dataSize = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(
                objectID,
                &address,
                0,
                nil,
                &dataSize,
                pointer
            )
        }
        return status == noErr ? value as String? : nil
    }

    private func pidProperty(_ objectID: AudioObjectID) -> pid_t? {
        var address = propertyAddress(selector: kAudioProcessPropertyPID)
        var pid = pid_t(0)
        var dataSize = UInt32(MemoryLayout<pid_t>.size)
        let status = AudioObjectGetPropertyData(
            objectID,
            &address,
            0,
            nil,
            &dataSize,
            &pid
        )
        return status == noErr && pid > 0 ? pid : nil
    }

    private func processName(for pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXCOMLEN))
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }

    private func processPath(for pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }

    private func parentProcessID(for pid: pid_t) -> pid_t? {
        var info = proc_bsdinfo()
        let expectedSize = MemoryLayout<proc_bsdinfo>.stride
        let result = proc_pidinfo(
            pid,
            PROC_PIDTBSDINFO,
            0,
            &info,
            Int32(expectedSize)
        )
        guard result == Int32(expectedSize), info.pbi_ppid > 0 else { return nil }
        return pid_t(info.pbi_ppid)
    }

    private func propertyAddress(
        selector: AudioObjectPropertySelector
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }
}

@available(macOS 15.0, *)
private final class ApplicationAudioProcessMonitor {
    var onChange: (() -> Void)?

    private let callbackQueue = DispatchQueue.main
    private var isStarted = false
    private var processListListener: AudioObjectPropertyListenerBlock?

    deinit {
        stop()
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true

        let processListListener: AudioObjectPropertyListenerBlock = {
            [weak self] _, _ in
            self?.onChange?()
        }
        self.processListListener = processListListener

        var address = propertyAddress(
            selector: kAudioHardwarePropertyProcessObjectList
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            callbackQueue,
            processListListener
        )
    }

    func stop() {
        if let processListListener {
            var address = propertyAddress(
                selector: kAudioHardwarePropertyProcessObjectList
            )
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                callbackQueue,
                processListListener
            )
        }

        processListListener = nil
        isStarted = false
    }

    private func propertyAddress(
        selector: AudioObjectPropertySelector
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }
}
