import Foundation

@main
enum MicrophoneAudioLevelTests {
    static func main() {
        testDecibelMapping()
        testDirectPresentationBehavior()
        testSegmentedPresentation()
        print("MicrophoneAudioLevelTests: passed")
    }

    private static func testDecibelMapping() {
        let silence = MicrophoneAudioLevel(rootMeanSquare: 0)
        expect(silence.normalized == 0, "silence should map to zero")
        expect(
            silence.decibelsFS == MicrophoneAudioLevel.minimumDecibelsFS,
            "silence should map to the display floor"
        )

        let minusThirty = MicrophoneAudioLevel(
            rootMeanSquare: pow(10, -30.0 / 20.0)
        )
        expect(
            abs(minusThirty.decibelsFS + 30) < 0.001,
            "-30 dBFS RMS should remain -30 dBFS"
        )
        expect(
            abs(minusThirty.normalized - 0.5) < 0.001,
            "-30 dBFS should map to the meter midpoint"
        )

        let fullScale = MicrophoneAudioLevel(rootMeanSquare: 1)
        expect(fullScale.decibelsFS == 0, "full scale should map to 0 dBFS")
        expect(fullScale.normalized == 1, "full scale should fill the meter")

        let invalid = MicrophoneAudioLevel(rootMeanSquare: .nan)
        expect(invalid == .silence, "invalid samples should fail closed to silence")
    }

    private static func testDirectPresentationBehavior() {
        let quiet = MicrophoneAudioLevel(
            rootMeanSquare: pow(10, -48.0 / 20.0)
        )
        let loud = MicrophoneAudioLevel(
            rootMeanSquare: pow(10, -6.0 / 20.0)
        )

        expect(
            abs(InputLevelPresentation.directLevel(for: quiet) - 0.2) < 0.001,
            "quiet input should be presented without temporal smoothing"
        )
        expect(
            abs(InputLevelPresentation.directLevel(for: loud) - 0.9) < 0.001,
            "the next loud input should replace the quiet input immediately"
        )
        expect(
            InputLevelPresentation.directLevel(for: .silence) == 0,
            "silence should replace a loud input immediately"
        )
    }

    private static func testSegmentedPresentation() {
        expect(
            SegmentedInputLevelPresentation.activeSegmentCount(
                for: 0,
                segmentCount: 36
            ) == 0,
            "zero input should keep every segment inactive"
        )
        expect(
            SegmentedInputLevelPresentation.activeSegmentCount(
                for: 0.8,
                segmentCount: 36
            ) == 29,
            "80 percent input should activate 29 of 36 segments"
        )
        expect(
            SegmentedInputLevelPresentation.activeSegmentCount(
                for: 2,
                segmentCount: 36
            ) == 36,
            "levels above one should clamp to the final segment"
        )
        expect(
            SegmentedInputLevelPresentation.activeSegmentCount(
                for: .nan,
                segmentCount: 36
            ) == 0,
            "invalid levels should fail closed to zero segments"
        )
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        guard condition() else {
            fputs("Test failed: \(message)\n", stderr)
            exit(1)
        }
    }
}
