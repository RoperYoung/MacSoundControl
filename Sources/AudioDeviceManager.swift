import AudioToolbox
import CoreAudio
import Foundation

struct AudioDevice: Equatable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let transportType: UInt32
    let sampleRate: Double

    var isVirtual: Bool {
        transportType == kAudioDeviceTransportTypeVirtual
    }

    var transportName: String {
        switch transportType {
        case kAudioDeviceTransportTypeBuiltIn:
            return "内建"
        case kAudioDeviceTransportTypeBluetooth:
            return "蓝牙"
        case kAudioDeviceTransportTypeBluetoothLE:
            return "蓝牙 LE"
        case kAudioDeviceTransportTypeUSB:
            return "USB"
        case kAudioDeviceTransportTypeFireWire:
            return "FireWire"
        case kAudioDeviceTransportTypeThunderbolt:
            return "雷雳"
        case kAudioDeviceTransportTypeHDMI:
            return "HDMI"
        case kAudioDeviceTransportTypeDisplayPort:
            return "DisplayPort"
        case kAudioDeviceTransportTypeAirPlay:
            return "隔空播放"
        case kAudioDeviceTransportTypeAggregate,
             kAudioDeviceTransportTypeAutoAggregate:
            return "聚合设备"
        case kAudioDeviceTransportTypeVirtual:
            return "虚拟"
        case kAudioDeviceTransportTypeContinuityCaptureWired:
            return "连续互通（有线）"
        case kAudioDeviceTransportTypeContinuityCaptureWireless:
            return "连续互通（无线）"
        default:
            return "音频设备"
        }
    }

    var sampleRateName: String {
        let kilohertz = sampleRate / 1_000
        if kilohertz.rounded() == kilohertz {
            return String(format: "%.0f kHz", kilohertz)
        }
        return String(format: "%.1f kHz", kilohertz)
    }

    var menuDetail: String {
        guard sampleRate > 0 else { return transportName }
        return "\(transportName) · \(sampleRateName)"
    }
}

struct OutputVolumeState: Equatable {
    let volume: Float
    let isMuted: Bool
    let canSetVolume: Bool
    let canSetMute: Bool
}

enum AudioDeviceManagerError: LocalizedError {
    case propertyRead(String, OSStatus)
    case propertyWrite(String, OSStatus)
    case propertyUnavailable(String)
    case deviceUnavailable

    var errorDescription: String? {
        switch self {
        case .propertyRead(let property, let status):
            return "无法读取\(property)（\(statusDescription(status))）"
        case .propertyWrite(let property, let status):
            return "无法修改\(property)（\(statusDescription(status))）"
        case .propertyUnavailable(let property):
            return "当前设备不支持\(property)"
        case .deviceUnavailable:
            return "这个音频设备已经不可用"
        }
    }

    private func statusDescription(_ status: OSStatus) -> String {
        let raw = UInt32(bitPattern: status)
        let bytes = [
            UInt8((raw >> 24) & 0xff),
            UInt8((raw >> 16) & 0xff),
            UInt8((raw >> 8) & 0xff),
            UInt8(raw & 0xff)
        ]

        if bytes.allSatisfy({ (32...126).contains($0) }),
           let code = String(bytes: bytes, encoding: .ascii) {
            return "'\(code)'"
        }
        return "\(status)"
    }
}

final class AudioDeviceManager {
    var onAudioSystemChanged: (() -> Void)?
    var onOutputVolumeChanged: (() -> Void)?

    private static let systemObject = AudioObjectID(kAudioObjectSystemObject)
    private var isDefaultInputListenerRegistered = false
    private var isDefaultOutputListenerRegistered = false
    private var isDevicesListenerRegistered = false
    private var monitoredOutputDeviceID: AudioDeviceID?
    private var monitoredOutputVolumeAddress: AudioObjectPropertyAddress?
    private var monitoredOutputMuteAddress: AudioObjectPropertyAddress?
    private var isOutputVolumeListenerRegistered = false
    private var isOutputMuteListenerRegistered = false

    private static let listenerProc: AudioObjectPropertyListenerProc = {
        _, _, _, clientData in
        guard let clientData else { return noErr }
        let manager = Unmanaged<AudioDeviceManager>
            .fromOpaque(clientData)
            .takeUnretainedValue()
        DispatchQueue.main.async { [weak manager] in
            manager?.refreshOutputVolumeMonitoring()
            manager?.onAudioSystemChanged?()
        }
        return noErr
    }

    private static let outputVolumeListenerProc: AudioObjectPropertyListenerProc = {
        _, _, _, clientData in
        guard let clientData else { return noErr }
        let manager = Unmanaged<AudioDeviceManager>
            .fromOpaque(clientData)
            .takeUnretainedValue()
        DispatchQueue.main.async { [weak manager] in
            manager?.onOutputVolumeChanged?()
        }
        return noErr
    }

    deinit {
        stopMonitoring()
    }

    func inputDevices() -> [AudioDevice] {
        devices(
            scope: kAudioObjectPropertyScopeInput,
            capabilitySelector: kAudioDevicePropertyDeviceCanBeDefaultDevice
        )
    }

    func outputDevices() -> [AudioDevice] {
        devices(
            scope: kAudioObjectPropertyScopeOutput,
            capabilitySelector: kAudioDevicePropertyDeviceCanBeDefaultDevice
        )
    }

    func defaultInputDevice() -> AudioDevice? {
        defaultDevice(
            selector: kAudioHardwarePropertyDefaultInputDevice,
            candidates: inputDevices()
        )
    }

    func defaultOutputDevice() -> AudioDevice? {
        defaultDevice(
            selector: kAudioHardwarePropertyDefaultOutputDevice,
            candidates: outputDevices()
        )
    }

    func setDefaultInputDevice(uid: String) throws {
        guard let target = inputDevices().first(where: { $0.uid == uid }) else {
            throw AudioDeviceManagerError.deviceUnavailable
        }
        try setDefaultDevice(
            id: target.id,
            selector: kAudioHardwarePropertyDefaultInputDevice,
            propertyName: "系统输入设备"
        )
    }

    func setDefaultOutputDevice(uid: String) throws {
        guard let target = outputDevices().first(where: { $0.uid == uid }) else {
            throw AudioDeviceManagerError.deviceUnavailable
        }
        try setDefaultDevice(
            id: target.id,
            selector: kAudioHardwarePropertyDefaultOutputDevice,
            propertyName: "系统输出设备"
        )
    }

    func outputVolumeState(for device: AudioDevice) -> OutputVolumeState? {
        guard let volumeAddress = outputVolumeAddress(for: device.id),
              let volume: Float32 = propertyValue(
                objectID: device.id,
                address: volumeAddress,
                initialValue: 0
              ) else {
            return nil
        }

        let muteAddress = outputMuteAddress(for: device.id)
        let muteValue: UInt32 = muteAddress.flatMap {
            propertyValue(objectID: device.id, address: $0, initialValue: 0)
        } ?? 0

        return OutputVolumeState(
            volume: max(0, min(1, volume)),
            isMuted: muteValue != 0,
            canSetVolume: isPropertySettable(
                objectID: device.id,
                address: volumeAddress
            ),
            canSetMute: muteAddress.map {
                isPropertySettable(objectID: device.id, address: $0)
            } ?? false
        )
    }

    func setOutputVolume(
        _ volume: Float,
        for device: AudioDevice,
        unmuteIfNeeded: Bool
    ) throws {
        guard let address = outputVolumeAddress(for: device.id),
              isPropertySettable(objectID: device.id, address: address) else {
            throw AudioDeviceManagerError.propertyUnavailable("系统音量调节")
        }

        var value = Float32(max(0, min(1, volume)))
        let status = writeProperty(
            objectID: device.id,
            address: address,
            value: &value
        )
        guard status == noErr else {
            throw AudioDeviceManagerError.propertyWrite("系统输出音量", status)
        }

        if value > 0, unmuteIfNeeded {
            try setOutputMuted(false, for: device)
        }
    }

    func setOutputMuted(_ muted: Bool, for device: AudioDevice) throws {
        guard let address = outputMuteAddress(for: device.id),
              isPropertySettable(objectID: device.id, address: address) else {
            throw AudioDeviceManagerError.propertyUnavailable("系统静音")
        }

        var value: UInt32 = muted ? 1 : 0
        let status = writeProperty(
            objectID: device.id,
            address: address,
            value: &value
        )
        guard status == noErr else {
            throw AudioDeviceManagerError.propertyWrite("系统静音", status)
        }
    }

    @discardableResult
    func startMonitoring() -> Bool {
        let clientData = Unmanaged.passUnretained(self).toOpaque()

        if !isDefaultInputListenerRegistered {
            isDefaultInputListenerRegistered = addListener(
                selector: kAudioHardwarePropertyDefaultInputDevice,
                clientData: clientData
            )
        }
        if !isDefaultOutputListenerRegistered {
            isDefaultOutputListenerRegistered = addListener(
                selector: kAudioHardwarePropertyDefaultOutputDevice,
                clientData: clientData
            )
        }
        if !isDevicesListenerRegistered {
            isDevicesListenerRegistered = addListener(
                selector: kAudioHardwarePropertyDevices,
                clientData: clientData
            )
        }

        refreshOutputVolumeMonitoring()

        return isDefaultInputListenerRegistered &&
            isDefaultOutputListenerRegistered &&
            isDevicesListenerRegistered
    }

    func stopMonitoring() {
        let clientData = Unmanaged.passUnretained(self).toOpaque()

        stopOutputVolumeMonitoring()

        if isDefaultInputListenerRegistered {
            removeListener(
                selector: kAudioHardwarePropertyDefaultInputDevice,
                clientData: clientData
            )
            isDefaultInputListenerRegistered = false
        }
        if isDefaultOutputListenerRegistered {
            removeListener(
                selector: kAudioHardwarePropertyDefaultOutputDevice,
                clientData: clientData
            )
            isDefaultOutputListenerRegistered = false
        }
        if isDevicesListenerRegistered {
            removeListener(
                selector: kAudioHardwarePropertyDevices,
                clientData: clientData
            )
            isDevicesListenerRegistered = false
        }
    }

    private func devices(
        scope: AudioObjectPropertyScope,
        capabilitySelector: AudioObjectPropertySelector
    ) -> [AudioDevice] {
        guard let deviceIDs = try? allDeviceIDs() else { return [] }

        return deviceIDs.compactMap { deviceID in
            guard hasStreams(deviceID, scope: scope),
                  scalarProperty(
                    objectID: deviceID,
                    selector: kAudioDevicePropertyDeviceIsAlive,
                    scope: kAudioObjectPropertyScopeGlobal,
                    defaultValue: UInt32(0)
                  ) != 0,
                  scalarProperty(
                    objectID: deviceID,
                    selector: capabilitySelector,
                    scope: scope,
                    defaultValue: UInt32(0)
                  ) != 0,
                  let name = stringProperty(
                    objectID: deviceID,
                    selector: kAudioObjectPropertyName,
                    scope: kAudioObjectPropertyScopeGlobal
                  ),
                  let uid = stringProperty(
                    objectID: deviceID,
                    selector: kAudioDevicePropertyDeviceUID,
                    scope: kAudioObjectPropertyScopeGlobal
                  ),
                  !isHidden(deviceID),
                  !uid.hasPrefix("MacSoundControl."),
                  !uid.hasPrefix("MicKeepAlive.") else {
                return nil
            }

            let transportType: UInt32 = scalarProperty(
                objectID: deviceID,
                selector: kAudioDevicePropertyTransportType,
                scope: kAudioObjectPropertyScopeGlobal,
                defaultValue: kAudioDeviceTransportTypeUnknown
            )
            let sampleRate: Float64 = scalarProperty(
                objectID: deviceID,
                selector: kAudioDevicePropertyNominalSampleRate,
                scope: kAudioObjectPropertyScopeGlobal,
                defaultValue: 0
            )

            return AudioDevice(
                id: deviceID,
                uid: uid,
                name: name,
                transportType: transportType,
                sampleRate: sampleRate
            )
        }
        .sorted {
            if $0.isVirtual != $1.isVirtual {
                return !$0.isVirtual
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private func isHidden(_ deviceID: AudioDeviceID) -> Bool {
        scalarProperty(
            objectID: deviceID,
            selector: kAudioDevicePropertyIsHidden,
            scope: kAudioObjectPropertyScopeGlobal,
            defaultValue: UInt32(0)
        ) != 0
    }

    private func outputVolumeAddress(
        for deviceID: AudioDeviceID
    ) -> AudioObjectPropertyAddress? {
        let selectors = [
            kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            kAudioDevicePropertyVolumeScalar
        ]

        for selector in selectors {
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioObjectPropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            if AudioObjectHasProperty(deviceID, &address) {
                return address
            }
        }
        return nil
    }

    private func outputMuteAddress(
        for deviceID: AudioDeviceID
    ) -> AudioObjectPropertyAddress? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        return AudioObjectHasProperty(deviceID, &address) ? address : nil
    }

    private func refreshOutputVolumeMonitoring() {
        let newDevice = defaultOutputDevice()
        let newVolumeAddress = newDevice.flatMap {
            outputVolumeAddress(for: $0.id)
        }
        let newMuteAddress = newDevice.flatMap {
            outputMuteAddress(for: $0.id)
        }

        if monitoredOutputDeviceID == newDevice?.id,
           monitoredOutputVolumeAddress?.mSelector == newVolumeAddress?.mSelector,
           monitoredOutputMuteAddress?.mSelector == newMuteAddress?.mSelector {
            return
        }

        stopOutputVolumeMonitoring()
        guard let newDevice else { return }

        monitoredOutputDeviceID = newDevice.id
        let clientData = Unmanaged.passUnretained(self).toOpaque()

        if var newVolumeAddress {
            let status = AudioObjectAddPropertyListener(
                newDevice.id,
                &newVolumeAddress,
                Self.outputVolumeListenerProc,
                clientData
            )
            if status == noErr {
                monitoredOutputVolumeAddress = newVolumeAddress
                isOutputVolumeListenerRegistered = true
            }
        }

        if var newMuteAddress {
            let status = AudioObjectAddPropertyListener(
                newDevice.id,
                &newMuteAddress,
                Self.outputVolumeListenerProc,
                clientData
            )
            if status == noErr {
                monitoredOutputMuteAddress = newMuteAddress
                isOutputMuteListenerRegistered = true
            }
        }
    }

    private func stopOutputVolumeMonitoring() {
        guard let deviceID = monitoredOutputDeviceID else { return }
        let clientData = Unmanaged.passUnretained(self).toOpaque()

        if isOutputVolumeListenerRegistered,
           var address = monitoredOutputVolumeAddress {
            AudioObjectRemovePropertyListener(
                deviceID,
                &address,
                Self.outputVolumeListenerProc,
                clientData
            )
        }
        if isOutputMuteListenerRegistered,
           var address = monitoredOutputMuteAddress {
            AudioObjectRemovePropertyListener(
                deviceID,
                &address,
                Self.outputVolumeListenerProc,
                clientData
            )
        }

        monitoredOutputDeviceID = nil
        monitoredOutputVolumeAddress = nil
        monitoredOutputMuteAddress = nil
        isOutputVolumeListenerRegistered = false
        isOutputMuteListenerRegistered = false
    }

    private func defaultDevice(
        selector: AudioObjectPropertySelector,
        candidates: [AudioDevice]
    ) -> AudioDevice? {
        let defaultID: AudioDeviceID = scalarProperty(
            objectID: Self.systemObject,
            selector: selector,
            scope: kAudioObjectPropertyScopeGlobal,
            defaultValue: kAudioObjectUnknown
        )
        guard defaultID != kAudioObjectUnknown else { return nil }
        return candidates.first(where: { $0.id == defaultID })
    }

    private func setDefaultDevice(
        id: AudioDeviceID,
        selector: AudioObjectPropertySelector,
        propertyName: String
    ) throws {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var mutableDeviceID = id
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectSetPropertyData(
            Self.systemObject,
            &address,
            0,
            nil,
            size,
            &mutableDeviceID
        )
        guard status == noErr else {
            throw AudioDeviceManagerError.propertyWrite(propertyName, status)
        }
    }

    private func addListener(
        selector: AudioObjectPropertySelector,
        clientData: UnsafeMutableRawPointer
    ) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        return AudioObjectAddPropertyListener(
            Self.systemObject,
            &address,
            Self.listenerProc,
            clientData
        ) == noErr
    }

    private func removeListener(
        selector: AudioObjectPropertySelector,
        clientData: UnsafeMutableRawPointer
    ) {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListener(
            Self.systemObject,
            &address,
            Self.listenerProc,
            clientData
        )
    }

    private func allDeviceIDs() throws -> [AudioDeviceID] {
        var lastStatus: OSStatus = kAudioHardwareUnspecifiedError

        for _ in 0..<2 {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDevices,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var dataSize: UInt32 = 0
            var status = AudioObjectGetPropertyDataSize(
                Self.systemObject,
                &address,
                0,
                nil,
                &dataSize
            )
            guard status == noErr else {
                lastStatus = status
                continue
            }
            guard dataSize > 0 else { return [] }

            var deviceIDs = [AudioDeviceID](
                repeating: kAudioObjectUnknown,
                count: Int(dataSize) / MemoryLayout<AudioDeviceID>.size
            )
            status = deviceIDs.withUnsafeMutableBufferPointer { buffer in
                guard let baseAddress = buffer.baseAddress else { return noErr }
                return AudioObjectGetPropertyData(
                    Self.systemObject,
                    &address,
                    0,
                    nil,
                    &dataSize,
                    baseAddress
                )
            }
            guard status == noErr else {
                lastStatus = status
                continue
            }

            let returnedCount = min(
                deviceIDs.count,
                Int(dataSize) / MemoryLayout<AudioDeviceID>.size
            )
            return Array(deviceIDs.prefix(returnedCount))
        }

        throw AudioDeviceManagerError.propertyRead("音频设备列表", lastStatus)
    }

    private func hasStreams(
        _ deviceID: AudioDeviceID,
        scope: AudioObjectPropertyScope
    ) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        return AudioObjectGetPropertyDataSize(
            deviceID,
            &address,
            0,
            nil,
            &dataSize
        ) == noErr && dataSize > 0
    }

    private func scalarProperty<T>(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        defaultValue: T
    ) -> T {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var value = defaultValue
        var dataSize = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutableBytes(of: &value) { bytes in
            AudioObjectGetPropertyData(
                objectID,
                &address,
                0,
                nil,
                &dataSize,
                bytes.baseAddress!
            )
        }
        return status == noErr ? value : defaultValue
    }

    private func propertyValue<T>(
        objectID: AudioObjectID,
        address: AudioObjectPropertyAddress,
        initialValue: T
    ) -> T? {
        var mutableAddress = address
        var value = initialValue
        var dataSize = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutableBytes(of: &value) { bytes in
            AudioObjectGetPropertyData(
                objectID,
                &mutableAddress,
                0,
                nil,
                &dataSize,
                bytes.baseAddress!
            )
        }
        return status == noErr ? value : nil
    }

    private func isPropertySettable(
        objectID: AudioObjectID,
        address: AudioObjectPropertyAddress
    ) -> Bool {
        var mutableAddress = address
        var settable = DarwinBoolean(false)
        return AudioObjectIsPropertySettable(
            objectID,
            &mutableAddress,
            &settable
        ) == noErr && settable.boolValue
    }

    private func writeProperty<T>(
        objectID: AudioObjectID,
        address: AudioObjectPropertyAddress,
        value: inout T
    ) -> OSStatus {
        var mutableAddress = address
        return withUnsafeBytes(of: &value) { bytes in
            AudioObjectSetPropertyData(
                objectID,
                &mutableAddress,
                0,
                nil,
                UInt32(bytes.count),
                bytes.baseAddress!
            )
        }
    }

    private func stringProperty(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(
            objectID,
            &address,
            0,
            nil,
            &dataSize,
            &value
        )
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
}
