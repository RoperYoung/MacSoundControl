import AppKit

final class ApplicationVolumeHeaderView: NSView {
    var onModeChange: ((ApplicationVolumeControlMode) -> Void)?

    private let titleLabel = NSTextField(
        labelWithString: "应用音量"
    )
    private let modeControl = NSSegmentedControl(
        labels: ["统一控制", "分开控制"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )

    private(set) var mode: ApplicationVolumeControlMode = .separate

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        MenuSectionTitleStyle.configure(titleLabel)
        addSubview(titleLabel)

        modeControl.controlSize = .small
        modeControl.segmentStyle = .automatic
        modeControl.setWidth(68, forSegment: 0)
        modeControl.setWidth(68, forSegment: 1)
        modeControl.target = self
        modeControl.action = #selector(selectControlMode)
        modeControl.setAccessibilityLabel("应用音量控制方式")
        addSubview(modeControl)

        setAccessibilityElement(false)
        configure(mode: .separate)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()

        let contentFrame = MenuSectionTitleStyle.contentFrame(in: bounds)
        let contentX = contentFrame.minX
        let contentMaxX = contentFrame.maxX
        let controlWidth: CGFloat = 136
        let controlHeight: CGFloat = 24
        let controlX = contentMaxX - controlWidth

        titleLabel.frame = NSRect(
            x: contentX,
            y: (bounds.height - MenuSectionTitleStyle.labelHeight) / 2,
            width: max(0, controlX - contentX - 10),
            height: MenuSectionTitleStyle.labelHeight
        )
        modeControl.frame = NSRect(
            x: controlX,
            y: (bounds.height - controlHeight) / 2,
            width: controlWidth,
            height: controlHeight
        )
    }

    func configure(mode: ApplicationVolumeControlMode) {
        self.mode = mode
        modeControl.selectedSegment = mode == .unified ? 0 : 1

        let explanation: String
        switch mode {
        case .unified:
            explanation = "统一控制：只使用上方系统输出音量，已保存的软件音量不会删除"
        case .separate:
            explanation = "分开控制：显示当前已注册音频输出的应用，并分别调节和保存音量"
        }
        toolTip = explanation
        modeControl.toolTip = explanation
        modeControl.setAccessibilityValue(
            mode == .unified ? "统一控制" : "分开控制"
        )
    }

    @objc private func selectControlMode() {
        let selectedMode: ApplicationVolumeControlMode = modeControl.selectedSegment == 0
            ? .unified
            : .separate
        guard selectedMode != mode else { return }
        configure(mode: selectedMode)
        onModeChange?(selectedMode)
    }
}
