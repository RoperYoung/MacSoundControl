import Foundation

private func expect(
    _ condition: @autoclosure () -> Bool,
    _ message: String
) {
    guard condition() else {
        fputs("OutputVolumeInteractionStateTests failed: \(message)\n", stderr)
        exit(1)
    }
}

@main
private enum OutputVolumeInteractionStateTests {
    static func main() {
        var state = OutputVolumeInteractionState()
        expect(state.shouldApplySystemRefresh(), "空闲时应接受系统刷新")

        state.beginTracking()
        expect(state.isTracking, "开始拖动后应记录跟踪状态")
        expect(!state.shouldApplySystemRefresh(), "拖动时不得用系统反读覆盖滑块")
        expect(state.hasDeferredSystemRefresh, "拖动时收到的系统刷新应被记录")

        state.noteLocalWrite()
        state.endTracking()
        expect(!state.isTracking, "松手后应退出跟踪状态")
        expect(
            state.isAwaitingAuthoritativeRefresh,
            "松手后应等待一次权威系统反读"
        )
        expect(
            !state.shouldApplySystemRefresh(),
            "松手后的短暂硬件回写窗口仍应抑制通知"
        )

        state.completeAuthoritativeRefresh()
        expect(
            state.shouldApplySystemRefresh(),
            "完成权威反读后应恢复外部音量通知"
        )
        expect(!state.hasDeferredSystemRefresh, "完成反读后应清除延迟标记")

        state.noteLocalWrite()
        expect(
            !state.shouldApplySystemRefresh(),
            "键盘或单击产生的本地写入也应等待系统校准"
        )
        state.reset()
        expect(state.shouldApplySystemRefresh(), "重置后应立即接受系统刷新")

        print("OutputVolumeInteractionStateTests: passed")
    }
}
