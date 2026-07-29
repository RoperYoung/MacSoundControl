import Foundation

@main
enum ApplicationVolumeControlModeTests {
    static func main() {
        expect(
            ApplicationVolumeControlMode.resolve(storedRawValue: nil) == .separate,
            "missing preference should preserve the existing separate-control behavior"
        )
        expect(
            ApplicationVolumeControlMode.resolve(storedRawValue: "unknown") == .separate,
            "unknown preference should fail closed to separate control"
        )
        expect(
            ApplicationVolumeControlMode.resolve(storedRawValue: "unified") == .unified,
            "unified preference should round-trip"
        )
        expect(
            ApplicationVolumeControlMode.resolve(storedRawValue: "separate") == .separate,
            "separate preference should round-trip"
        )
        expect(
            ApplicationVolumeTargetPolicy.effectiveVolume(
                savedVolume: 0.37,
                individualControlEnabled: false
            ) == 1,
            "unified control should submit unity without deleting the saved volume"
        )
        expect(
            ApplicationVolumeTargetPolicy.effectiveVolume(
                savedVolume: 0.37,
                individualControlEnabled: true
            ) == 0.37,
            "separate control should restore the saved per-application volume"
        )
        print("ApplicationVolumeControlModeTests: passed")
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
