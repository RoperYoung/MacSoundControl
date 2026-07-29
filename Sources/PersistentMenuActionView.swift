import AppKit

enum PersistentMenuActionStyle {
    case selection
    case device(symbolName: String, detail: String)
}

final class PersistentMenuActionView: NSView {
    var onActivate: (() -> Void)?

    private let indicatorLabel = NSTextField(labelWithString: "✓")
    private let iconBackgroundView = NSView()
    private let iconImageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let actionButton = NSButton()
    private var pointerTrackingArea: NSTrackingArea?
    private var hoverState = PersistentMenuHoverState()
    private var title: String
    private let style: PersistentMenuActionStyle

    private(set) var isSelected: Bool
    private(set) var isActionEnabled: Bool = true

    init(
        frame frameRect: NSRect,
        title: String,
        isSelected: Bool = false,
        style: PersistentMenuActionStyle = .selection
    ) {
        self.title = title
        self.isSelected = isSelected
        self.style = style
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.cornerRadius = style.isDevice ? 8 : 5

        indicatorLabel.font = .systemFont(
            ofSize: NSFont.systemFontSize,
            weight: .semibold
        )
        indicatorLabel.alignment = .center
        indicatorLabel.lineBreakMode = .byClipping
        addSubview(indicatorLabel)

        iconBackgroundView.wantsLayer = true
        iconBackgroundView.layer?.cornerRadius = 12
        addSubview(iconBackgroundView)

        iconImageView.imageAlignment = .alignCenter
        iconImageView.imageScaling = .scaleProportionallyDown
        addSubview(iconImageView)

        titleLabel.font = .menuFont(ofSize: 13.5)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.stringValue = title
        addSubview(titleLabel)

        detailLabel.font = .systemFont(ofSize: 12.5, weight: .medium)
        detailLabel.alignment = .right
        detailLabel.lineBreakMode = .byTruncatingTail
        addSubview(detailLabel)

        if case .device(let symbolName, let detail) = style {
            let symbol = NSImage(
                systemSymbolName: symbolName,
                accessibilityDescription: nil
            )?.withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            )
            symbol?.isTemplate = true
            iconImageView.image = symbol
            detailLabel.stringValue = detail
        }

        actionButton.title = ""
        actionButton.isBordered = false
        actionButton.isTransparent = true
        actionButton.focusRingType = .none
        actionButton.target = self
        actionButton.action = #selector(activate)
        addSubview(actionButton)

        updatePresentation()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()

        switch style {
        case .selection:
            let indicatorX: CGFloat = 11
            let indicatorWidth: CGFloat = 18
            indicatorLabel.frame = NSRect(
                x: indicatorX,
                y: 5,
                width: indicatorWidth,
                height: max(20, bounds.height - 10)
            )
            titleLabel.frame = NSRect(
                x: indicatorLabel.frame.maxX + 4,
                y: 5,
                width: max(0, bounds.width - indicatorLabel.frame.maxX - 16),
                height: max(20, bounds.height - 10)
            )

        case .device:
            let iconFrame = NSRect(
                x: 16,
                y: (bounds.height - 30) / 2,
                width: 30,
                height: 30
            )
            iconBackgroundView.frame = iconFrame
            iconBackgroundView.layer?.cornerRadius = 15
            iconImageView.frame = iconFrame.insetBy(dx: 7, dy: 7)

            let detailWidth: CGFloat = 128
            detailLabel.frame = NSRect(
                x: bounds.width - detailWidth - 16,
                y: (bounds.height - 20) / 2,
                width: detailWidth,
                height: 20
            )
            titleLabel.frame = NSRect(
                x: 58,
                y: (bounds.height - 22) / 2,
                width: max(0, detailLabel.frame.minX - 68),
                height: 22
            )
        }
        actionButton.frame = bounds
    }

    override func updateTrackingAreas() {
        if let pointerTrackingArea {
            removeTrackingArea(pointerTrackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        pointerTrackingArea = trackingArea
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        hoverState.pointerEntered()
        updatePresentation()
    }

    override func mouseExited(with event: NSEvent) {
        hoverState.pointerExited()
        updatePresentation()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updatePresentation()
    }

    func clearPointerHighlight() {
        guard hoverState.reconcile(actualContainsPointer: false) else { return }
        updatePresentation()
    }

    func reconcilePointerHighlightWithCurrentLocation() {
        let actualContainsPointer: Bool
        if let window, !isHiddenOrHasHiddenAncestor {
            let pointInWindow = window.convertPoint(
                fromScreen: NSEvent.mouseLocation
            )
            let pointInView = convert(pointInWindow, from: nil)
            actualContainsPointer = bounds.contains(pointInView)
        } else {
            actualContainsPointer = false
        }

        guard hoverState.reconcile(
            actualContainsPointer: actualContainsPointer
        ) else { return }
        updatePresentation()
    }

    func configure(
        title: String? = nil,
        isSelected: Bool? = nil,
        isEnabled: Bool? = nil,
        toolTip: String? = nil
    ) {
        if let title {
            self.title = title
            titleLabel.stringValue = title
        }
        if let isSelected {
            self.isSelected = isSelected
        }
        if let isEnabled {
            isActionEnabled = isEnabled
        }
        if let toolTip {
            self.toolTip = toolTip
            actionButton.toolTip = toolTip
        }
        updatePresentation()
    }

    @objc private func activate() {
        guard isActionEnabled else { return }
        onActivate?()
    }

    private func updatePresentation() {
        indicatorLabel.isHidden = style.isDevice || !isSelected
        iconBackgroundView.isHidden = !style.isDevice
        iconImageView.isHidden = !style.isDevice
        detailLabel.isHidden = !style.isDevice
        indicatorLabel.textColor = isActionEnabled
            ? .labelColor
            : .disabledControlTextColor
        titleLabel.textColor = isActionEnabled
            ? .labelColor
            : .disabledControlTextColor
        detailLabel.textColor = isActionEnabled
            ? .secondaryLabelColor
            : .disabledControlTextColor
        titleLabel.font = style.isDevice
            ? .systemFont(
                ofSize: 14,
                weight: isSelected ? .semibold : .regular
            )
            : .menuFont(ofSize: 13.5)

        if style.isDevice {
            iconBackgroundView.layer?.backgroundColor = isSelected
                ? NSColor.controlAccentColor
                    .withAlphaComponent(isActionEnabled ? 1 : 0.45)
                    .cgColor
                : NSColor.labelColor.withAlphaComponent(0.075).cgColor
            iconImageView.contentTintColor = isSelected
                ? NSColor.white.withAlphaComponent(isActionEnabled ? 1 : 0.7)
                : (isActionEnabled
                    ? .secondaryLabelColor
                    : .disabledControlTextColor)
        }
        actionButton.isEnabled = isActionEnabled
        let accessibilityLabel: String
        if case .device(_, let detail) = style {
            accessibilityLabel = "\(title)，\(detail)"
        } else {
            accessibilityLabel = title
        }
        actionButton.setAccessibilityLabel(accessibilityLabel)
        actionButton.setAccessibilityValue(isSelected ? "已选择" : "未选择")

        if isActionEnabled, hoverState.isPointerInside {
            layer?.backgroundColor = NSColor.labelColor
                .withAlphaComponent(0.06)
                .cgColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
        }
    }
}

private extension PersistentMenuActionStyle {
    var isDevice: Bool {
        if case .device = self {
            return true
        }
        return false
    }
}
