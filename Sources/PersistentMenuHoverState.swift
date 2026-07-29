struct PersistentMenuHoverState: Equatable {
    private(set) var isPointerInside = false

    mutating func pointerEntered() {
        isPointerInside = true
    }

    mutating func pointerExited() {
        isPointerInside = false
    }

    @discardableResult
    mutating func reconcile(actualContainsPointer: Bool) -> Bool {
        let changed = isPointerInside != actualContainsPointer
        isPointerInside = actualContainsPointer
        return changed
    }
}
