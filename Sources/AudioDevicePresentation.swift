import CoreAudio
import Foundation

enum AudioDevicePresentationDirection {
    case input
    case output
}

enum AudioDevicePresentation {
    static func symbolName(
        deviceName: String,
        transportType: UInt32,
        direction: AudioDevicePresentationDirection
    ) -> String {
        let name = deviceName.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        ).lowercased()

        if transportType == kAudioDeviceTransportTypeVirtual {
            return "waveform"
        }

        if isPhone(name: name, transportType: transportType) {
            return "iphone"
        }

        switch direction {
        case .input:
            if isComputer(name: name, transportType: transportType) {
                return isDesktopComputer(name: name)
                    ? "desktopcomputer"
                    : "laptopcomputer"
            }
            if isHeadset(name: name, transportType: transportType) {
                return "headphones"
            }
            return "mic.fill"

        case .output:
            if isDisplay(name: name, transportType: transportType) {
                return "display"
            }
            if transportType == kAudioDeviceTransportTypeAirPlay {
                return "airplayaudio"
            }
            if isComputer(name: name, transportType: transportType) {
                return isDesktopComputer(name: name)
                    ? "desktopcomputer"
                    : "laptopcomputer"
            }
            if isHeadset(name: name, transportType: transportType) {
                return "headphones"
            }
            return "hifispeaker.fill"
        }
    }

    private static func isPhone(name: String, transportType: UInt32) -> Bool {
        switch transportType {
        case kAudioDeviceTransportTypeContinuityCaptureWired,
             kAudioDeviceTransportTypeContinuityCaptureWireless:
            return true
        default:
            return containsAny(name, ["iphone", "ipad", "手机", "电话"])
        }
    }

    private static func isDisplay(name: String, transportType: UInt32) -> Bool {
        switch transportType {
        case kAudioDeviceTransportTypeHDMI,
             kAudioDeviceTransportTypeDisplayPort:
            return true
        default:
            return containsAny(
                name,
                ["monitor", "display", "显示器", "屏幕", "电视", " tv"]
            )
        }
    }

    private static func isComputer(name: String, transportType: UInt32) -> Bool {
        if containsAny(
            name,
            ["macbook", "imac", "mac mini", "mac studio", "mac pro", "内建"]
        ) {
            return true
        }
        return transportType == kAudioDeviceTransportTypeBuiltIn
    }

    private static func isDesktopComputer(name: String) -> Bool {
        containsAny(name, ["imac", "mac mini", "mac studio", "mac pro", "台式"])
    }

    private static func isHeadset(name: String, transportType: UInt32) -> Bool {
        if containsAny(
            name,
            [
                "headphone", "headset", "earphone", "airpods", "earbuds",
                "buds", "耳机", "mchose", "dji mic",
            ]
        ) {
            return true
        }

        switch transportType {
        case kAudioDeviceTransportTypeBluetooth,
             kAudioDeviceTransportTypeBluetoothLE:
            return true
        default:
            return false
        }
    }

    private static func containsAny(_ value: String, _ needles: [String]) -> Bool {
        needles.contains { value.contains($0) }
    }
}
