import AppKit

private final class TrackingSlider: NSSlider {
    var onTrackingChange: ((Bool) -> Void)?

    override func mouseDown(with event: NSEvent) {
        onTrackingChange?(true)
        super.mouseDown(with: event)
        onTrackingChange?(false)
    }
}

final class OutputVolumeMenuView: NSView {
    var onVolumeChange: ((Float, Bool) -> Void)?
    var onTrackingChange: ((Bool) -> Void)?
    var onToggleMute: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "系统输出音量")
    private let valueLabel = NSTextField(labelWithString: "—")
    private let muteButton = NSButton()
    private let slider = TrackingSlider()
    private let maximumIconView = NSImageView()

    private var state: OutputVolumeState?
    private var deviceName: String?
    private var displayedVolumeSymbolName: String?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        MenuSectionTitleStyle.configure(titleLabel)
        addSubview(titleLabel)

        valueLabel.font = .monospacedDigitSystemFont(
            ofSize: 12.5,
            weight: .regular
        )
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right
        addSubview(valueLabel)

        muteButton.title = ""
        muteButton.isBordered = false
        muteButton.focusRingType = .none
        muteButton.target = self
        muteButton.action = #selector(toggleMute)
        addSubview(muteButton)

        slider.minValue = 0
        slider.maxValue = 1
        slider.doubleValue = 0
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(changeVolume)
        slider.onTrackingChange = { [weak self] isTracking in
            self?.onTrackingChange?(isTracking)
        }
        slider.setAccessibilityLabel("系统输出音量")
        addSubview(slider)

        maximumIconView.image = symbol(named: "speaker.wave.3.fill")
        maximumIconView.imageScaling = .scaleProportionallyDown
        maximumIconView.contentTintColor = .labelColor
        maximumIconView.setAccessibilityElement(false)
        addSubview(maximumIconView)

        setAccessibilityElement(false)
        updatePresentation()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()

        let contentFrame = MenuSectionTitleStyle.contentFrame(in: bounds)
        let contentX = contentFrame.minX
        let contentWidth = contentFrame.width
        let contentMaxX = contentFrame.maxX
        titleLabel.frame = NSRect(
            x: contentX,
            y: bounds.height - 23,
            width: max(0, contentWidth - 104),
            height: MenuSectionTitleStyle.labelHeight
        )
        valueLabel.frame = NSRect(
            x: contentMaxX - 64,
            y: bounds.height - 22,
            width: 64,
            height: 18
        )
        muteButton.frame = NSRect(x: contentX, y: 5, width: 20, height: 20)
        maximumIconView.frame = NSRect(
            x: contentMaxX - 20,
            y: 5,
            width: 20,
            height: 20
        )
        slider.frame = NSRect(
            x: muteButton.frame.maxX + 9,
            y: 3,
            width: maximumIconView.frame.minX - muteButton.frame.maxX - 18,
            height: 24
        )
    }

    func configure(deviceName: String?, state newState: OutputVolumeState?) {
        self.deviceName = deviceName
        state = newState
        updatePresentation()
    }

    func showError(_ message: String) {
        titleLabel.stringValue = "系统输出音量 · 调节失败"
        titleLabel.toolTip = message
    }

    @objc private func changeVolume() {
        guard let state, state.canSetVolume else { return }

        let volume = Float(slider.doubleValue)
        let shouldUnmute = volume > 0 && state.isMuted && state.canSetMute
        let isMuted = shouldUnmute ? false : state.isMuted
        self.state = OutputVolumeState(
            volume: volume,
            isMuted: isMuted,
            canSetVolume: state.canSetVolume,
            canSetMute: state.canSetMute
        )
        updateInteractiveVolumePresentation(volume: volume, isMuted: isMuted)
        onVolumeChange?(volume, shouldUnmute)
    }

    @objc private func toggleMute() {
        guard state?.canSetMute == true else { return }
        onToggleMute?()
    }

    private func updatePresentation() {
        let volume = state?.volume ?? 0
        let isMuted = state?.isMuted ?? false
        let canSetVolume = state?.canSetVolume == true
        let canSetMute = state?.canSetMute == true
        let percentage = Int((volume * 100).rounded())

        if deviceName == nil {
            titleLabel.stringValue = "系统输出音量 · 没有可用的输出设备"
            valueLabel.stringValue = "—"
        } else if state == nil || !canSetVolume {
            titleLabel.stringValue = "系统输出音量 · 当前设备不支持"
            valueLabel.stringValue = "—"
        } else {
            titleLabel.stringValue = "系统输出音量"
            updateInteractiveVolumePresentation(
                volume: volume,
                isMuted: isMuted
            )
        }
        titleLabel.toolTip = deviceName.map { "当前系统输出：\($0)" }

        slider.doubleValue = Double(volume)
        slider.isEnabled = canSetVolume
        slider.setAccessibilityValue(isMuted ? "静音" : "\(percentage)%")
        slider.toolTip = canSetVolume
            ? "拖动以调节 \(deviceName ?? "当前输出") 的系统音量"
            : "当前输出设备由外部硬件控制音量"

        muteButton.isEnabled = canSetMute
        muteButton.contentTintColor = canSetMute ? .labelColor : .disabledControlTextColor
        updateMuteButtonPresentation(volume: volume, isMuted: isMuted)

        maximumIconView.contentTintColor = canSetVolume
            ? .labelColor
            : .disabledControlTextColor
    }

    private func updateInteractiveVolumePresentation(
        volume: Float,
        isMuted: Bool
    ) {
        let percentage = Int((volume * 100).rounded())
        valueLabel.stringValue = isMuted ? "静音" : "\(percentage)%"
        slider.setAccessibilityValue(isMuted ? "静音" : "\(percentage)%")
        updateMuteButtonPresentation(volume: volume, isMuted: isMuted)
    }

    private func updateMuteButtonPresentation(
        volume: Float,
        isMuted: Bool
    ) {
        let symbolName = isMuted
            ? "speaker.slash.fill"
            : volumeSymbol(for: volume)
        if displayedVolumeSymbolName != symbolName {
            muteButton.image = symbol(named: symbolName)
            displayedVolumeSymbolName = symbolName
        }
        muteButton.setAccessibilityLabel(isMuted ? "取消静音" : "静音")
        muteButton.toolTip = state?.canSetMute == true
            ? (isMuted ? "取消静音" : "静音")
            : "当前输出不支持系统静音"
    }

    private func volumeSymbol(for volume: Float) -> String {
        switch volume {
        case ..<0.01:
            return "speaker.fill"
        case ..<0.34:
            return "speaker.wave.1.fill"
        case ..<0.67:
            return "speaker.wave.2.fill"
        default:
            return "speaker.wave.3.fill"
        }
    }

    private func symbol(named name: String) -> NSImage? {
        let image = NSImage(
            systemSymbolName: name,
            accessibilityDescription: nil
        )
        image?.isTemplate = true
        return image
    }
}
