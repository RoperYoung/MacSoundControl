import Foundation

enum ApplicationVolumeTargetPolicy {
    static func effectiveVolume(
        savedVolume: Double,
        individualControlEnabled: Bool
    ) -> Double {
        individualControlEnabled ? savedVolume : 1
    }
}
