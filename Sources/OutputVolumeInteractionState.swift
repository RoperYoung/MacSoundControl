struct OutputVolumeInteractionState: Equatable {
    private(set) var isTracking = false
    private(set) var isAwaitingAuthoritativeRefresh = false
    private(set) var hasDeferredSystemRefresh = false

    mutating func beginTracking() {
        isTracking = true
        isAwaitingAuthoritativeRefresh = false
        hasDeferredSystemRefresh = false
    }

    mutating func noteLocalWrite() {
        isAwaitingAuthoritativeRefresh = true
    }

    mutating func endTracking() {
        isTracking = false
        isAwaitingAuthoritativeRefresh = true
    }

    mutating func shouldApplySystemRefresh() -> Bool {
        guard !isTracking, !isAwaitingAuthoritativeRefresh else {
            hasDeferredSystemRefresh = true
            return false
        }
        return true
    }

    mutating func completeAuthoritativeRefresh() {
        isAwaitingAuthoritativeRefresh = false
        hasDeferredSystemRefresh = false
    }

    mutating func reset() {
        self = OutputVolumeInteractionState()
    }
}
