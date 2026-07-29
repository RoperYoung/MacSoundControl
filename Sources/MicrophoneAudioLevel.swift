import Foundation

struct MicrophoneAudioLevel: Equatable {
    static let minimumDecibelsFS: Float = -60
    static let maximumDecibelsFS: Float = 0
    static let silence = MicrophoneAudioLevel(
        normalized: 0,
        decibelsFS: minimumDecibelsFS
    )

    let normalized: Float
    let decibelsFS: Float

    init(rootMeanSquare: Float) {
        let finiteRootMeanSquare = rootMeanSquare.isFinite
            ? max(rootMeanSquare, 0)
            : 0
        let rawDecibels = finiteRootMeanSquare > 0
            ? 20 * log10(finiteRootMeanSquare)
            : Self.minimumDecibelsFS
        let clampedDecibels = max(
            Self.minimumDecibelsFS,
            min(Self.maximumDecibelsFS, rawDecibels)
        )

        decibelsFS = clampedDecibels
        normalized = (clampedDecibels - Self.minimumDecibelsFS) /
            (Self.maximumDecibelsFS - Self.minimumDecibelsFS)
    }

    private init(normalized: Float, decibelsFS: Float) {
        self.normalized = normalized
        self.decibelsFS = decibelsFS
    }

    static func decibelsFS(forNormalized normalized: Double) -> Double {
        let clamped = max(0, min(1, normalized.isFinite ? normalized : 0))
        return Double(minimumDecibelsFS) +
            clamped * Double(maximumDecibelsFS - minimumDecibelsFS)
    }
}

enum InputLevelPresentation {
    static func directLevel(for level: MicrophoneAudioLevel) -> Double {
        let value = Double(level.normalized)
        return max(0, min(1, value.isFinite ? value : 0))
    }
}

enum SegmentedInputLevelPresentation {
    static func activeSegmentCount(
        for normalizedLevel: Double,
        segmentCount: Int
    ) -> Int {
        guard segmentCount > 0 else { return 0 }
        let finiteLevel = normalizedLevel.isFinite ? normalizedLevel : 0
        let clampedLevel = max(0, min(1, finiteLevel))
        return min(
            segmentCount,
            max(0, Int((clampedLevel * Double(segmentCount)).rounded()))
        )
    }
}
