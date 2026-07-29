import Foundation

private func expect(
    _ condition: @autoclosure () -> Bool,
    _ message: String
) {
    guard condition() else {
        fputs("PersistentMenuHoverStateTests failed: \(message)\n", stderr)
        exit(1)
    }
}

@main
private enum PersistentMenuHoverStateTests {
    static func main() {
        var state = PersistentMenuHoverState()
        expect(!state.isPointerInside, "初始状态不应显示悬停")

        state.pointerEntered()
        expect(state.isPointerInside, "mouseEntered 后应显示悬停")

        let clearedStaleState = state.reconcile(actualContainsPointer: false)
        expect(clearedStaleState, "菜单重排后应覆盖旧的进入状态")
        expect(!state.isPointerInside, "鼠标不在新 frame 内时必须清除悬停")

        let adoptedNewRow = state.reconcile(actualContainsPointer: true)
        expect(adoptedNewRow, "新位置位于鼠标下方时应采用当前状态")
        expect(state.isPointerInside, "当前真正位于鼠标下方的行应有反馈")

        let unchanged = state.reconcile(actualContainsPointer: true)
        expect(!unchanged, "相同的真实位置不应产生重复状态变化")

        state.pointerExited()
        expect(!state.isPointerInside, "mouseExited 后应清除悬停")

        print("PersistentMenuHoverStateTests: passed")
    }
}
