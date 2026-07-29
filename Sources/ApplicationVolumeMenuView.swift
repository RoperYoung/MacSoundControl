import AppKit

final class ApplicationVolumeMenuView: NSView {
    var onVolumeChange: ((String, Double) -> Void)?

    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "100%")
    private let slider = NSSlider()

    private var applicationID: String = ""
    private var applicationName: String = ""

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.imageFrameStyle = .none
        iconView.setAccessibilityElement(false)
        addSubview(iconView)

        nameLabel.font = .menuFont(ofSize: 13.5)
        nameLabel.textColor = .labelColor
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.maximumNumberOfLines = 1
        addSubview(nameLabel)

        valueLabel.font = .monospacedDigitSystemFont(
            ofSize: 12.5,
            weight: .regular
        )
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right
        addSubview(valueLabel)

        slider.minValue = 0
        slider.maxValue = 1
        slider.doubleValue = 1
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(changeVolume)
        addSubview(slider)

        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()

        let horizontalInset: CGFloat = 16
        let iconSize: CGFloat = 26
        let iconNameGap: CGFloat = 10
        let nameWidth: CGFloat = 128
        let nameSliderGap: CGFloat = 10
        let sliderValueGap: CGFloat = 8
        let valueWidth: CGFloat = 48
        let controlHeight: CGFloat = 24
        let textHeight: CGFloat = 20

        let nameX = horizontalInset + iconSize + iconNameGap
        let sliderX = nameX + nameWidth + nameSliderGap
        let valueX = bounds.width - horizontalInset - valueWidth
        let sliderMaxX = valueX - sliderValueGap

        iconView.frame = NSRect(
            x: horizontalInset,
            y: (bounds.height - iconSize) / 2,
            width: iconSize,
            height: iconSize
        )
        nameLabel.frame = NSRect(
            x: nameX,
            y: (bounds.height - textHeight) / 2,
            width: nameWidth,
            height: textHeight
        )
        valueLabel.frame = NSRect(
            x: valueX,
            y: (bounds.height - textHeight) / 2,
            width: valueWidth,
            height: textHeight
        )
        slider.frame = NSRect(
            x: sliderX,
            y: (bounds.height - controlHeight) / 2,
            width: max(0, sliderMaxX - sliderX),
            height: controlHeight
        )
    }

    func configure(application: OutputAudioApplication) {
        applicationID = application.id
        applicationName = application.name
        nameLabel.stringValue = application.name
        nameLabel.toolTip = application.name

        let resolvedIcon = application.icon ?? application.bundleURL.map {
            NSWorkspace.shared.icon(forFile: $0.path)
        }
        if let resolvedIcon {
            iconView.image = (resolvedIcon.copy() as? NSImage) ?? resolvedIcon
            iconView.isHidden = false
            iconView.toolTip = application.name
        } else {
            iconView.image = nil
            iconView.isHidden = true
            iconView.toolTip = nil
        }
        slider.doubleValue = application.volume
        slider.setAccessibilityLabel("\(application.name) 音量")
        slider.toolTip = "只调节 \(application.name) 的输出音量"
        updateValueLabel()
        needsLayout = true
    }

    @objc private func changeVolume() {
        updateValueLabel()
        onVolumeChange?(applicationID, slider.doubleValue)
    }

    private func updateValueLabel() {
        let percentage = Int((slider.doubleValue * 100).rounded())
        valueLabel.stringValue = "\(percentage)%"
        slider.setAccessibilityValue("\(percentage)%")
        valueLabel.toolTip = "\(applicationName)：\(percentage)%"
    }
}
