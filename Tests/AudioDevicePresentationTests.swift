import CoreAudio
import Foundation

@main
enum AudioDevicePresentationTests {
    static func main() {
        expectSymbol(
            "display",
            name: "Mi monitor (HDMI)",
            transport: kAudioDeviceTransportTypeHDMI,
            direction: .output
        )
        expectSymbol(
            "laptopcomputer",
            name: "MacBook Pro 扬声器",
            transport: kAudioDeviceTransportTypeBuiltIn,
            direction: .output
        )
        expectSymbol(
            "desktopcomputer",
            name: "iMac 麦克风",
            transport: kAudioDeviceTransportTypeBuiltIn,
            direction: .input
        )
        expectSymbol(
            "headphones",
            name: "DJI Mic Mini 2S",
            transport: kAudioDeviceTransportTypeBluetooth,
            direction: .input
        )
        expectSymbol(
            "iphone",
            name: "Neo's iPhone 麦克风",
            transport: kAudioDeviceTransportTypeContinuityCaptureWired,
            direction: .input
        )
        expectSymbol(
            "waveform",
            name: "BlackHole 2ch",
            transport: kAudioDeviceTransportTypeVirtual,
            direction: .output
        )
        expectSymbol(
            "mic.fill",
            name: "Studio USB Microphone",
            transport: kAudioDeviceTransportTypeUSB,
            direction: .input
        )
        expectSymbol(
            "hifispeaker.fill",
            name: "USB Audio DAC",
            transport: kAudioDeviceTransportTypeUSB,
            direction: .output
        )
        print("AudioDevicePresentationTests: passed")
    }

    private static func expectSymbol(
        _ expected: String,
        name: String,
        transport: UInt32,
        direction: AudioDevicePresentationDirection
    ) {
        let actual = AudioDevicePresentation.symbolName(
            deviceName: name,
            transportType: transport,
            direction: direction
        )
        guard actual == expected else {
            fputs(
                "AudioDevicePresentationTests failed: \(name) expected \(expected), got \(actual)\n",
                stderr
            )
            exit(1)
        }
    }
}
