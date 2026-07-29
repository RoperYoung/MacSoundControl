import AppKit

enum MenuSectionTitleStyle {
    static let preferredContentWidth: CGFloat = 428
    static let minimumHorizontalInset: CGFloat = 12
    static let labelHeight: CGFloat = 20

    static func configure(_ label: NSTextField) {
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
    }

    static func contentFrame(in bounds: NSRect) -> NSRect {
        let contentWidth = min(
            preferredContentWidth,
            max(0, bounds.width - (minimumHorizontalInset * 2))
        )
        return NSRect(
            x: (bounds.width - contentWidth) / 2,
            y: 0,
            width: contentWidth,
            height: bounds.height
        )
    }
}

final class MenuSectionHeaderView: NSView {
    private let titleLabel: NSTextField

    init(frame frameRect: NSRect, title: String) {
        titleLabel = NSTextField(labelWithString: title)
        super.init(frame: frameRect)

        MenuSectionTitleStyle.configure(titleLabel)
        titleLabel.setAccessibilityLabel(title)
        addSubview(titleLabel)

        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()

        let contentFrame = MenuSectionTitleStyle.contentFrame(in: bounds)
        titleLabel.frame = NSRect(
            x: contentFrame.minX,
            y: (bounds.height - MenuSectionTitleStyle.labelHeight) / 2,
            width: contentFrame.width,
            height: MenuSectionTitleStyle.labelHeight
        )
    }
}
