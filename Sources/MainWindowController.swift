import AppKit

private enum MainWindowLayoutMetrics {
    static let contentLeadingInset: CGFloat = 24
    static let contentTrailingInset: CGFloat = 34
    static let maximumContentWidth: CGFloat = 620
}

private enum MainWindowTypography {
    static let sectionTitle = NSFont.systemFont(ofSize: 14, weight: .semibold)
    static let primaryRow = NSFont.systemFont(ofSize: 13, weight: .medium)
    static let secondary = NSFont.systemFont(ofSize: 12, weight: .regular)
    static let secondaryMedium = NSFont.systemFont(ofSize: 12, weight: .medium)
    static let tertiary = NSFont.systemFont(ofSize: 11.5, weight: .regular)
}

struct MainWindowDeviceSnapshot {
    let uid: String
    let name: String
    let detail: String
    let symbolName: String
    let isSelected: Bool
}

struct MainWindowOutputVolumeSnapshot {
    let deviceName: String?
    let state: OutputVolumeState?
}

enum MainWindowMicrophoneTestPhase: Equatable {
    case idle
    case preparing
    case testing
    case failed(message: String)
}

struct MainWindowMicrophoneTestSnapshot {
    let device: MainWindowDeviceSnapshot?
    let phase: MainWindowMicrophoneTestPhase
}

struct MainWindowSnapshot {
    let inputDevices: [MainWindowDeviceSnapshot]
    let outputDevices: [MainWindowDeviceSnapshot]
    let outputVolume: MainWindowOutputVolumeSnapshot
    let applicationVolumeMode: ApplicationVolumeControlMode
    let applicationVolumeSupportState: ApplicationVolumeSupportState
    let applications: [OutputAudioApplication]
    let keepAliveEnabled: Bool
    let virtualDevicesVisible: Bool
    let launchAtLoginEnabled: Bool
    let launchAtLoginRequiresApproval: Bool
    let canReconnectInput: Bool
    let microphonePermissionDenied: Bool
    let microphoneTest: MainWindowMicrophoneTestSnapshot
    let statusMessage: String?
    let versionText: String
}

struct MainWindowActions {
    let showMenu: () -> Void
    let selectInput: (String) -> Void
    let selectOutput: (String) -> Void
    let setOutputVolume: (Float, Bool) -> Void
    let setOutputVolumeTracking: (Bool) -> Void
    let toggleOutputMute: () -> Void
    let setApplicationVolumeMode: (ApplicationVolumeControlMode) -> Void
    let setApplicationVolume: (String, Double) -> Void
    let setApplicationVolumeTracking: (Bool) -> Void
    let toggleKeepAlive: () -> Void
    let toggleVirtualDevices: () -> Void
    let toggleLaunchAtLogin: () -> Void
    let reconnectInput: () -> Void
    let requestApplicationAudioPermission: () -> Void
    let openApplicationAudioPrivacySettings: () -> Void
    let openMicrophonePrivacySettings: () -> Void
    let startInputTest: () -> Void
    let stopInputTest: () -> Void
    let openThirdPartyNotices: () -> Void
    let quitApplication: () -> Void

    static func previewActions(
        onStartInputTest: @escaping () -> Void = {}
    ) -> MainWindowActions {
        MainWindowActions(
            showMenu: {},
            selectInput: { _ in },
            selectOutput: { _ in },
            setOutputVolume: { _, _ in },
            setOutputVolumeTracking: { _ in },
            toggleOutputMute: {},
            setApplicationVolumeMode: { _ in },
            setApplicationVolume: { _, _ in },
            setApplicationVolumeTracking: { _ in },
            toggleKeepAlive: {},
            toggleVirtualDevices: {},
            toggleLaunchAtLogin: {},
            reconnectInput: {},
            requestApplicationAudioPermission: {},
            openApplicationAudioPrivacySettings: {},
            openMicrophonePrivacySettings: {},
            startInputTest: onStartInputTest,
            stopInputTest: {},
            openThirdPartyNotices: {},
            quitApplication: {}
        )
    }

    static let preview = previewActions()
}

enum MainWindowDestination: CaseIterable, Hashable {
    case outputVolume
    case applicationVolume
    case outputDevices
    case inputDevices
    case residencyAndStartup
    case inputTest
    case about

    var title: String {
        switch self {
        case .outputVolume: return "系统输出音量"
        case .applicationVolume: return "应用音量"
        case .outputDevices: return "选择系统输出"
        case .inputDevices: return "选择系统输入"
        case .residencyAndStartup: return "常驻与启动"
        case .inputTest: return "声音测试"
        case .about: return "关于"
        }
    }

    var symbolName: String {
        switch self {
        case .outputVolume: return "speaker.wave.2.fill"
        case .applicationVolume: return "slider.horizontal.3"
        case .outputDevices: return "hifispeaker.fill"
        case .inputDevices: return "mic.fill"
        case .residencyAndStartup: return "power"
        case .inputTest: return "waveform"
        case .about: return "info.circle"
        }
    }
}

final class MainWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    private let rootViewController: MainWindowSplitViewController
    private let actions: MainWindowActions

    init(snapshot: MainWindowSnapshot, actions: MainWindowActions) {
        self.actions = actions
        rootViewController = MainWindowSplitViewController(
            snapshot: snapshot,
            actions: actions
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 700),
            styleMask: [
                .titled,
                .closable,
                .miniaturizable,
                .resizable,
                .fullSizeContentView,
            ],
            backing: .buffered,
            defer: false
        )
        window.title = "MacSoundControl"
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.toolbarStyle = .unified
        window.isOpaque = true
        window.backgroundColor = .textBackgroundColor
        window.isMovableByWindowBackground = false
        window.contentMinSize = NSSize(width: 820, height: 600)
        window.contentViewController = rootViewController
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("MacSoundControl.MainWindow")

        super.init(window: window)

        let toolbar = NSToolbar(identifier: "MacSoundControl.MainWindow.Toolbar")
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.showsBaselineSeparator = false
        toolbar.delegate = self
        window.toolbar = toolbar
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(snapshot: MainWindowSnapshot) {
        rootViewController.update(snapshot: snapshot)
    }

    func pushMicrophoneLevel(_ level: MicrophoneAudioLevel) {
        rootViewController.pushMicrophoneLevel(level)
    }

    func present(destination: MainWindowDestination = .outputVolume) {
        rootViewController.select(destination: destination)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showAbout() {
        present(destination: .about)
    }

    #if DEBUG
    func setReferenceViewportForVisualQA() {
        guard let window else { return }
        var frame = window.frame
        frame.size = NSSize(width: 844, height: 697)
        window.setFrame(frame, display: true)
    }
    #endif

    func windowWillClose(_ notification: Notification) {
        actions.stopInputTest()
    }

    func toolbarDefaultItemIdentifiers(
        _ toolbar: NSToolbar
    ) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .sidebarTrackingSeparator]
    }

    func toolbarAllowedItemIdentifiers(
        _ toolbar: NSToolbar
    ) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .sidebarTrackingSeparator]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case .toggleSidebar:
            let item = NSToolbarItem(itemIdentifier: .toggleSidebar)
            item.label = "显示或隐藏侧栏"
            item.paletteLabel = "侧栏"
            item.toolTip = "显示或隐藏侧栏"
            item.target = rootViewController
            item.action = #selector(NSSplitViewController.toggleSidebar(_:))
            item.isNavigational = true
            return item
        case .sidebarTrackingSeparator:
            return NSTrackingSeparatorToolbarItem(
                identifier: .sidebarTrackingSeparator,
                splitView: rootViewController.splitView,
                dividerIndex: 0
            )
        default:
            return nil
        }
    }
}

private final class SolidContentBackgroundView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        updateColor()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColor()
    }

    private func updateColor() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        }
    }
}

private final class MainWindowSplitViewController: NSSplitViewController {
    private let sidebarViewController = MainSidebarViewController()
    private let contentViewController: MainContentViewController
    private let sidebarItem: NSSplitViewItem

    init(snapshot: MainWindowSnapshot, actions: MainWindowActions) {
        contentViewController = MainContentViewController(
            snapshot: snapshot,
            actions: actions
        )
        sidebarItem = NSSplitViewItem(
            sidebarWithViewController: sidebarViewController
        )
        super.init(nibName: nil, bundle: nil)

        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.autosaveName = "MacSoundControl.MainWindow.SplitView"

        sidebarItem.minimumThickness = 158
        sidebarItem.maximumThickness = 260
        sidebarItem.preferredThicknessFraction = 0.19
        sidebarItem.canCollapse = true
        sidebarItem.allowsFullHeightLayout = true
        sidebarItem.titlebarSeparatorStyle = .none

        let contentItem = NSSplitViewItem(
            viewController: contentViewController
        )
        contentItem.minimumThickness = 560
        contentItem.holdingPriority = .defaultLow

        addSplitViewItem(sidebarItem)
        addSplitViewItem(contentItem)

        sidebarViewController.onSelectDestination = { [weak self] destination in
            self?.contentViewController.select(
                destination: destination,
                animated: true
            )
        }
        contentViewController.onVisibleDestinationChange = { [weak self] destination in
            self?.sidebarViewController.setSelectedDestination(destination)
        }
        sidebarViewController.setSelectedDestination(.outputVolume)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(snapshot: MainWindowSnapshot) {
        contentViewController.update(snapshot: snapshot)
    }

    func pushMicrophoneLevel(_ level: MicrophoneAudioLevel) {
        contentViewController.pushMicrophoneLevel(level)
    }

    func select(destination: MainWindowDestination) {
        sidebarViewController.setSelectedDestination(destination)
        contentViewController.select(destination: destination, animated: true)
    }
}

private final class MainSidebarItem: NSObject {
    let destination: MainWindowDestination

    init(destination: MainWindowDestination) {
        self.destination = destination
    }
}

private final class MainSidebarCellView: NSTableCellView {
    private let symbolView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        symbolView.imageScaling = .scaleProportionallyDown
        symbolView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 13.5, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        imageView = symbolView
        textField = titleLabel
        addSubview(symbolView)
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            symbolView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            symbolView.centerYAnchor.constraint(equalTo: centerYAnchor),
            symbolView.widthAnchor.constraint(equalToConstant: 16),
            symbolView.heightAnchor.constraint(equalToConstant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: symbolView.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(destination: MainWindowDestination) {
        titleLabel.stringValue = destination.title
        symbolView.image = NSImage(
            systemSymbolName: destination.symbolName,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        )
        setAccessibilityLabel(destination.title)
    }
}

private final class SidebarNeutralOverlayView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = NSUserInterfaceItemIdentifier("MainSidebarNeutralOverlay")
        wantsLayer = true
        updateColor()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColor()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    private func updateColor() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.textBackgroundColor
                .withAlphaComponent(0.75)
                .cgColor
        }
    }
}

private final class MainSidebarViewController: NSViewController,
    NSOutlineViewDataSource,
    NSOutlineViewDelegate {
    var onSelectDestination: ((MainWindowDestination) -> Void)?

    private let items = MainWindowDestination.allCases.map {
        MainSidebarItem(destination: $0)
    }
    private let scrollView = NSScrollView()
    private let outlineView = NSOutlineView()
    private var pendingDestination: MainWindowDestination = .outputVolume
    private var isUpdatingSelection = false

    override func loadView() {
        let materialView = NSVisualEffectView(
            frame: NSRect(x: 0, y: 0, width: 180, height: 700)
        )
        materialView.material = .sidebar
        materialView.blendingMode = .withinWindow
        materialView.state = .followsWindowActiveState
        view = materialView

        let neutralOverlay = SidebarNeutralOverlayView(frame: .zero)
        neutralOverlay.translatesAutoresizingMaskIntoConstraints = false
        materialView.addSubview(neutralOverlay)

        let column = NSTableColumn(
            identifier: NSUserInterfaceItemIdentifier("MainSidebarColumn")
        )
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.style = .sourceList
        outlineView.rowHeight = 30
        outlineView.intercellSpacing = NSSize(width: 0, height: 3)
        outlineView.indentationPerLevel = 0
        outlineView.floatsGroupRows = false
        outlineView.allowsMultipleSelection = false
        outlineView.allowsEmptySelection = false
        outlineView.backgroundColor = .clear
        outlineView.focusRingType = .none
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.setAccessibilityLabel("主窗口导航")

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.documentView = outlineView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            neutralOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            neutralOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            neutralOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            neutralOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            scrollView.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor,
                constant: 8
            ),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
        ])

        outlineView.reloadData()
        setSelectedDestination(pendingDestination)
    }

    func setSelectedDestination(_ destination: MainWindowDestination) {
        pendingDestination = destination
        guard isViewLoaded,
              let row = items.firstIndex(where: { $0.destination == destination }) else {
            return
        }
        guard outlineView.selectedRow != row else { return }

        isUpdatingSelection = true
        outlineView.selectRowIndexes(
            IndexSet(integer: row),
            byExtendingSelection: false
        )
        outlineView.scrollRowToVisible(row)
        isUpdatingSelection = false
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        numberOfChildrenOfItem item: Any?
    ) -> Int {
        item == nil ? items.count : 0
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        child index: Int,
        ofItem item: Any?
    ) -> Any {
        items[index]
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        isItemExpandable item: Any
    ) -> Bool {
        false
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        viewFor tableColumn: NSTableColumn?,
        item: Any
    ) -> NSView? {
        guard let sidebarItem = item as? MainSidebarItem else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("MainSidebarCell")
        let cell: MainSidebarCellView
        if let reusable = outlineView.makeView(
            withIdentifier: identifier,
            owner: self
        ) as? MainSidebarCellView {
            cell = reusable
        } else {
            cell = MainSidebarCellView()
            cell.identifier = identifier
        }
        cell.configure(destination: sidebarItem.destination)
        return cell
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !isUpdatingSelection else { return }
        let row = outlineView.selectedRow
        guard items.indices.contains(row) else { return }
        let destination = items[row].destination
        pendingDestination = destination
        onSelectDestination?(destination)
    }
}

private final class MainContentViewController: NSViewController {
    private let audioControlView: AudioControlView
    var onVisibleDestinationChange: ((MainWindowDestination) -> Void)? {
        didSet {
            audioControlView.onVisibleDestinationChange = onVisibleDestinationChange
        }
    }

    private var pendingDestination: MainWindowDestination? = .outputVolume
    private var hasCompletedInitialLayout = false

    init(snapshot: MainWindowSnapshot, actions: MainWindowActions) {
        audioControlView = AudioControlView(snapshot: snapshot, actions: actions)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = SolidContentBackgroundView(
            frame: NSRect(x: 0, y: 0, width: 780, height: 700)
        )
        audioControlView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(audioControlView)

        NSLayoutConstraint.activate([
            audioControlView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            audioControlView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            audioControlView.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor
            ),
            audioControlView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        audioControlView.layoutSubtreeIfNeeded()
        if let pendingDestination {
            self.pendingDestination = nil
            audioControlView.scroll(
                to: pendingDestination,
                animated: hasCompletedInitialLayout
            )
        }
        hasCompletedInitialLayout = true
    }

    func update(snapshot: MainWindowSnapshot) {
        audioControlView.update(snapshot: snapshot)
    }

    func pushMicrophoneLevel(_ level: MicrophoneAudioLevel) {
        audioControlView.pushMicrophoneLevel(level)
    }

    func select(destination: MainWindowDestination, animated: Bool) {
        if hasCompletedInitialLayout {
            audioControlView.scroll(to: destination, animated: animated)
        } else {
            pendingDestination = destination
        }
    }
}

private final class AudioControlView: NSView {
    var onVisibleDestinationChange: ((MainWindowDestination) -> Void)?

    private let scrollView = NSScrollView()
    private let documentView: AudioControlDocumentView
    private var programmaticDestination: MainWindowDestination?
    private var lastReportedDestination: MainWindowDestination?

    init(snapshot: MainWindowSnapshot, actions: MainWindowActions) {
        documentView = AudioControlDocumentView(snapshot: snapshot, actions: actions)
        super.init(frame: .zero)

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = documentView
        scrollView.contentView.postsBoundsChangedNotifications = true
        addSubview(scrollView)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scrollBoundsDidChange),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        documentView.layoutContent(
            width: scrollView.contentView.bounds.width,
            viewportHeight: scrollView.contentView.bounds.height
        )
    }

    func update(snapshot: MainWindowSnapshot) {
        let previousOrigin = scrollView.contentView.bounds.origin
        documentView.update(snapshot: snapshot)
        documentView.layoutContent(
            width: scrollView.contentView.bounds.width,
            viewportHeight: scrollView.contentView.bounds.height
        )
        scrollView.contentView.scroll(to: constrained(origin: previousOrigin))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        reportVisibleDestination()
    }

    func pushMicrophoneLevel(_ level: MicrophoneAudioLevel) {
        documentView.pushMicrophoneLevel(level)
    }

    func scroll(to destination: MainWindowDestination, animated _: Bool) {
        layoutSubtreeIfNeeded()
        guard let anchorY = documentView.anchorOffset(for: destination) else {
            return
        }

        let target = constrained(origin: NSPoint(x: 0, y: max(0, anchorY - 10)))
        programmaticDestination = destination
        lastReportedDestination = destination
        onVisibleDestinationChange?(destination)

        let finish: () -> Void = { [weak self] in
            guard let self else { return }
            self.programmaticDestination = nil
            self.scrollView.reflectScrolledClipView(self.scrollView.contentView)
            self.reportVisibleDestination(force: true)
        }

        scrollView.contentView.scroll(to: target)
        finish()
    }

    @objc private func scrollBoundsDidChange() {
        guard programmaticDestination == nil else { return }
        reportVisibleDestination()
    }

    private func reportVisibleDestination(force: Bool = false) {
        let visibleBounds = scrollView.contentView.bounds
        let destination: MainWindowDestination?
        if visibleBounds.maxY >= documentView.bounds.height - 1 {
            destination = MainWindowDestination.allCases.last
        } else {
            destination = documentView.destination(at: visibleBounds.minY + 72)
        }
        guard let destination else { return }
        guard force || destination != lastReportedDestination else { return }
        lastReportedDestination = destination
        onVisibleDestinationChange?(destination)
    }

    private func constrained(origin: NSPoint) -> NSPoint {
        let maximumY = max(
            0,
            documentView.bounds.height - scrollView.contentView.bounds.height
        )
        return NSPoint(
            x: 0,
            y: min(max(0, origin.y), maximumY)
        )
    }
}

private class FlatSectionView: NSView {
    override var isFlipped: Bool { true }

    var showsBottomSeparator = true {
        didSet {
            if oldValue != showsBottomSeparator {
                needsDisplay = true
            }
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard showsBottomSeparator, bounds.width > 1, bounds.height > 1 else {
            return
        }

        effectiveAppearance.performAsCurrentDrawingAppearance {
            NSColor.separatorColor.withAlphaComponent(0.32).setStroke()
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 0, y: bounds.maxY - 0.5))
            path.line(to: NSPoint(x: bounds.maxX, y: bounds.maxY - 0.5))
            path.lineWidth = 1
            path.stroke()
        }
    }
}

private final class SemanticSeparatorView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        updateColor()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColor()
    }

    private func updateColor() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.separatorColor
                .withAlphaComponent(0.28)
                .cgColor
        }
    }
}

private final class AudioControlDocumentView: NSView {
    override var isFlipped: Bool { true }

    private var snapshot: MainWindowSnapshot
    private let actions: MainWindowActions
    private let microphoneTestView: MainWindowMicrophoneTestView
    private let aboutView: AboutMacSoundControlView
    private var anchorOffsets: [MainWindowDestination: CGFloat] = [:]
    private var lastLayoutWidth: CGFloat = 0
    private var lastViewportHeight: CGFloat = 0

    init(snapshot: MainWindowSnapshot, actions: MainWindowActions) {
        self.snapshot = snapshot
        self.actions = actions
        microphoneTestView = MainWindowMicrophoneTestView(
            inputDevices: snapshot.inputDevices,
            snapshot: snapshot.microphoneTest,
            onSelectInput: actions.selectInput,
            onStart: actions.startInputTest,
            onStop: actions.stopInputTest,
            onOpenPrivacy: actions.openMicrophonePrivacySettings
        )
        aboutView = AboutMacSoundControlView(
            versionText: snapshot.versionText,
            onOpenThirdPartyNotices: actions.openThirdPartyNotices
        )
        super.init(frame: NSRect(x: 0, y: 0, width: 700, height: 900))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(snapshot: MainWindowSnapshot) {
        self.snapshot = snapshot
        microphoneTestView.update(
            inputDevices: snapshot.inputDevices,
            snapshot: snapshot.microphoneTest
        )
        aboutView.update(versionText: snapshot.versionText)
        rebuild(width: max(lastLayoutWidth, bounds.width))
    }

    func pushMicrophoneLevel(_ level: MicrophoneAudioLevel) {
        microphoneTestView.pushLevel(level)
    }

    func layoutContent(width: CGFloat, viewportHeight: CGFloat) {
        let normalizedWidth = max(560, width)
        let normalizedViewportHeight = max(400, viewportHeight)
        guard abs(normalizedWidth - lastLayoutWidth) >= 0.5
            || abs(normalizedViewportHeight - lastViewportHeight) >= 0.5
        else { return }
        lastLayoutWidth = normalizedWidth
        lastViewportHeight = normalizedViewportHeight
        rebuild(width: normalizedWidth)
    }

    func anchorOffset(for destination: MainWindowDestination) -> CGFloat? {
        anchorOffsets[destination]
    }

    func destination(at verticalPosition: CGFloat) -> MainWindowDestination? {
        var current: MainWindowDestination?
        for destination in MainWindowDestination.allCases {
            guard let offset = anchorOffsets[destination] else { continue }
            if offset <= verticalPosition {
                current = destination
            } else {
                break
            }
        }
        return current ?? MainWindowDestination.allCases.first
    }

    private func rebuild(width: CGFloat) {
        subviews.forEach { $0.removeFromSuperview() }
        anchorOffsets.removeAll(keepingCapacity: true)

        let horizontalInset = MainWindowLayoutMetrics.contentLeadingInset
        let contentWidth = min(
            MainWindowLayoutMetrics.maximumContentWidth,
            max(
                0,
                width
                    - horizontalInset
                    - MainWindowLayoutMetrics.contentTrailingInset
            )
        )
        let sectionSpacing: CGFloat = 52
        var y: CGFloat = 18

        anchorOffsets[.outputVolume] = y
        let outputVolumeView = MainOutputVolumeControlView(
            snapshot: snapshot.outputVolume,
            onVolumeChange: actions.setOutputVolume,
            onTrackingChange: actions.setOutputVolumeTracking,
            onToggleMute: actions.toggleOutputMute
        )
        outputVolumeView.frame = NSRect(
            x: horizontalInset,
            y: y,
            width: contentWidth,
            height: MainOutputVolumeControlView.preferredHeight
        )
        addSubview(outputVolumeView)
        y += MainOutputVolumeControlView.preferredHeight + sectionSpacing

        anchorOffsets[.applicationVolume] = y
        y = addApplicationSection(
            x: horizontalInset,
            y: y,
            width: contentWidth,
            sectionSpacing: sectionSpacing
        )
        anchorOffsets[.outputDevices] = y
        y = addDeviceSection(
            title: "选择系统输出",
            devices: snapshot.outputDevices,
            x: horizontalInset,
            y: y,
            width: contentWidth,
            action: actions.selectOutput,
            emptyMessage: "没有可显示的输出设备",
            sectionSpacing: sectionSpacing
        )
        anchorOffsets[.inputDevices] = y
        y = addDeviceSection(
            title: "选择系统输入",
            devices: snapshot.inputDevices,
            x: horizontalInset,
            y: y,
            width: contentWidth,
            action: actions.selectInput,
            emptyMessage: "没有可显示的输入设备",
            sectionSpacing: sectionSpacing
        )
        anchorOffsets[.residencyAndStartup] = y
        y = addSettingsSection(
            x: horizontalInset,
            y: y,
            width: contentWidth,
            sectionSpacing: sectionSpacing
        )

        anchorOffsets[.inputTest] = y
        let microphoneSectionHeight: CGFloat = 390
        microphoneTestView.frame = NSRect(
            x: horizontalInset,
            y: y,
            width: contentWidth,
            height: microphoneSectionHeight
        )
        addSubview(microphoneTestView)
        y += microphoneSectionHeight + sectionSpacing

        anchorOffsets[.about] = y
        let aboutSectionHeight: CGFloat = 438
        aboutView.frame = NSRect(
            x: horizontalInset,
            y: y,
            width: contentWidth,
            height: aboutSectionHeight
        )
        addSubview(aboutView)
        y += aboutSectionHeight

        let bottomPadding: CGFloat = 24
        frame = NSRect(
            x: 0,
            y: 0,
            width: width,
            height: max(y + bottomPadding, lastViewportHeight)
        )
    }

    private func addApplicationSection(
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        sectionSpacing: CGFloat
    ) -> CGFloat {
        let panel = FlatSectionView(frame: .zero)
        let innerX: CGFloat = 0
        let innerWidth = width
        var localY: CGFloat = 0

        let title = makePanelTitle("应用音量")
        title.frame = NSRect(
            x: innerX,
            y: localY,
            width: max(0, innerWidth - 210),
            height: 26
        )
        panel.addSubview(title)

        let appModeView = MainApplicationModeView(
            mode: snapshot.applicationVolumeMode,
            onModeChange: actions.setApplicationVolumeMode
        )
        appModeView.frame = NSRect(
            x: max(innerX, innerWidth - 188),
            y: localY - 3,
            width: 188,
            height: 32
        )
        panel.addSubview(appModeView)
        localY += 44

        if snapshot.applicationVolumeMode == .separate {
            switch snapshot.applicationVolumeSupportState {
            case .unsupported:
                localY = addPanelInfoRow(
                    "分应用音量需要 macOS 15 或更高版本。",
                    to: panel,
                    x: innerX,
                    y: localY,
                    width: innerWidth
                )
            case .needsPermission:
                localY = addPanelInfoRow(
                    "需要“系统音频录制”权限后才能分别控制应用。",
                    to: panel,
                    x: innerX,
                    y: localY,
                    width: innerWidth
                )
                localY = addPanelActionButtons(
                    [
                        ("重新请求权限", actions.requestApplicationAudioPermission),
                        ("打开系统权限设置…", actions.openApplicationAudioPrivacySettings),
                    ],
                    to: panel,
                    x: innerX,
                    y: localY,
                    width: innerWidth
                )
            case .failed(let message):
                localY = addPanelInfoRow(
                    "应用音量暂不可用：\(message)",
                    to: panel,
                    x: innerX,
                    y: localY,
                    width: innerWidth
                )
            case .ready:
                if snapshot.applications.isEmpty {
                    localY = addPanelInfoRow(
                        "当前没有可单独控制的应用。",
                        to: panel,
                        x: innerX,
                        y: localY,
                        width: innerWidth
                    )
                } else {
                    for application in snapshot.applications {
                        let row = MainApplicationVolumeRow(
                            application: application,
                            onVolumeChange: actions.setApplicationVolume,
                            onTrackingChange: actions.setApplicationVolumeTracking
                        )
                        row.frame = NSRect(
                            x: innerX,
                            y: localY,
                            width: innerWidth,
                            height: 42
                        )
                        panel.addSubview(row)
                        localY += 44
                    }
                }
            }
        }

        let panelHeight = localY + 12
        panel.frame = NSRect(x: x, y: y, width: width, height: panelHeight)
        addSubview(panel)
        return y + panelHeight + sectionSpacing
    }

    private func addDeviceSection(
        title: String,
        devices: [MainWindowDeviceSnapshot],
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        action: @escaping (String) -> Void,
        emptyMessage: String,
        sectionSpacing: CGFloat
    ) -> CGFloat {
        let panel = FlatSectionView(frame: .zero)
        let innerX: CGFloat = 0
        let innerWidth = width
        var localY: CGFloat = 0

        let titleLabel = makePanelTitle(title)
        titleLabel.frame = NSRect(x: innerX, y: localY, width: innerWidth, height: 26)
        panel.addSubview(titleLabel)
        localY += 34

        if devices.isEmpty {
            localY = addPanelInfoRow(
                emptyMessage,
                to: panel,
                x: innerX,
                y: localY,
                width: innerWidth
            )
        } else {
            for device in devices {
                let row = MainDeviceSelectionRow(device: device) {
                    action(device.uid)
                }
                row.frame = NSRect(
                    x: innerX,
                    y: localY,
                    width: innerWidth,
                    height: 44
                )
                panel.addSubview(row)
                localY += 44
            }
        }

        let panelHeight = localY + 10
        panel.frame = NSRect(x: x, y: y, width: width, height: panelHeight)
        addSubview(panel)
        return y + panelHeight + sectionSpacing
    }

    private func addSettingsSection(
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        sectionSpacing: CGFloat
    ) -> CGFloat {
        let panel = FlatSectionView(frame: .zero)
        let innerX: CGFloat = 0
        let innerWidth = width
        var localY: CGFloat = 0

        let title = makePanelTitle("常驻与启动")
        title.frame = NSRect(x: innerX, y: localY, width: innerWidth, height: 26)
        panel.addSubview(title)
        localY += 34

        let settingRows: [(String, String, Bool, () -> Void)] = [
            (
                "开启麦克风常驻",
                "",
                snapshot.keepAliveEnabled,
                actions.toggleKeepAlive
            ),
            (
                "展示虚拟设备",
                "",
                snapshot.virtualDevicesVisible,
                actions.toggleVirtualDevices
            ),
            (
                "开机自动启动",
                snapshot.launchAtLoginRequiresApproval
                    ? "需要在系统设置的登录项中批准"
                    : "",
                snapshot.launchAtLoginEnabled,
                actions.toggleLaunchAtLogin
            ),
        ]
        for (title, detail, isOn, action) in settingRows {
            let row = MainToggleRow(
                title: title,
                detail: detail,
                isOn: isOn,
                onToggle: action
            )
            row.frame = NSRect(
                x: innerX,
                y: localY,
                width: innerWidth,
                height: 44
            )
            panel.addSubview(row)
            localY += 44
        }

        if snapshot.canReconnectInput {
            localY += 8
            let reconnectButton = ClosureButton(
                title: "重新打开当前输入通道",
                action: actions.reconnectInput
            )
            reconnectButton.bezelStyle = .rounded
            reconnectButton.frame = NSRect(
                x: innerX,
                y: localY,
                width: innerWidth,
                height: 32
            )
            panel.addSubview(reconnectButton)
            localY += 38
        }

        let panelHeight = localY + 10
        panel.frame = NSRect(x: x, y: y, width: width, height: panelHeight)
        addSubview(panel)
        return y + panelHeight + sectionSpacing
    }

    private func makePanelTitle(_ title: String) -> NSTextField {
        makeLabel(
            title,
            font: MainWindowTypography.sectionTitle,
            color: .labelColor
        )
    }

    private func addPanelInfoRow(
        _ text: String,
        to panel: NSView,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat
    ) -> CGFloat {
        let row = MainInfoRow(text: text)
        row.frame = NSRect(x: x, y: y, width: width, height: 34)
        panel.addSubview(row)
        return y + 38
    }

    private func addPanelActionButtons(
        _ actions: [(String, () -> Void)],
        to panel: NSView,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        disabledTitles: Set<String> = []
    ) -> CGFloat {
        guard !actions.isEmpty else { return y }

        let gap: CGFloat = 8
        let buttonWidth = max(120, (width - gap) / 2)
        var currentX = x
        var currentY = y
        for (index, entry) in actions.enumerated() {
            if index > 0, index % 2 == 0 {
                currentX = x
                currentY += 38
            }
            let button = ClosureButton(title: entry.0, action: entry.1)
            button.bezelStyle = .rounded
            button.isEnabled = !disabledTitles.contains(entry.0)
            button.frame = NSRect(
                x: currentX,
                y: currentY,
                width: buttonWidth,
                height: 32
            )
            panel.addSubview(button)
            currentX += buttonWidth + gap
        }
        let rowCount = CGFloat((actions.count + 1) / 2)
        return y + (rowCount * 38)
    }

}

private final class MainOutputVolumeControlView: FlatSectionView {
    static let preferredHeight: CGFloat = 124

    private let titleLabel = NSTextField(labelWithString: "系统输出音量")
    private let deviceLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "—")
    private let muteButton = NSButton()
    private let slider = MainTrackingSlider()
    private let maximumIcon = NSImageView()
    private let minimumIcon = NSImageView()
    private var outputState: OutputVolumeState?
    private let onVolumeChange: (Float, Bool) -> Void
    private let onToggleMute: () -> Void

    init(
        snapshot: MainWindowOutputVolumeSnapshot,
        onVolumeChange: @escaping (Float, Bool) -> Void,
        onTrackingChange: @escaping (Bool) -> Void,
        onToggleMute: @escaping () -> Void
    ) {
        self.onVolumeChange = onVolumeChange
        self.onToggleMute = onToggleMute
        super.init(frame: .zero)

        titleLabel.font = MainWindowTypography.sectionTitle
        addSubview(titleLabel)

        deviceLabel.font = MainWindowTypography.secondary
        deviceLabel.textColor = .secondaryLabelColor
        deviceLabel.lineBreakMode = .byTruncatingTail
        addSubview(deviceLabel)

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        valueLabel.alignment = .right
        valueLabel.textColor = .secondaryLabelColor
        addSubview(valueLabel)

        muteButton.title = ""
        muteButton.isBordered = false
        muteButton.imagePosition = .imageLeading
        muteButton.controlSize = .regular
        muteButton.target = self
        muteButton.action = #selector(toggleMute)
        addSubview(muteButton)

        slider.minValue = 0
        slider.maxValue = 1
        slider.isContinuous = true
        slider.isVertical = false
        slider.target = self
        slider.action = #selector(changeVolume)
        slider.onTrackingChange = onTrackingChange
        slider.setAccessibilityLabel("系统输出音量")
        addSubview(slider)

        maximumIcon.image = systemSymbol("speaker.wave.3.fill", pointSize: 15)
        maximumIcon.imageScaling = .scaleProportionallyDown
        addSubview(maximumIcon)

        minimumIcon.image = systemSymbol("speaker.fill", pointSize: 13)
        minimumIcon.imageScaling = .scaleProportionallyDown
        addSubview(minimumIcon)

        configure(snapshot: snapshot)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        titleLabel.frame = NSRect(x: 0, y: 0, width: 190, height: 22)
        valueLabel.frame = NSRect(
            x: max(218, bounds.width - 78),
            y: 0,
            width: 78,
            height: 22
        )
        deviceLabel.frame = NSRect(
            x: 0,
            y: 26,
            width: max(0, bounds.width),
            height: 19
        )
        minimumIcon.frame = NSRect(x: 0, y: 55, width: 18, height: 18)
        slider.frame = NSRect(
            x: 28,
            y: 49,
            width: max(120, bounds.width - 70),
            height: 28
        )
        maximumIcon.frame = NSRect(
            x: bounds.width - 22,
            y: 54,
            width: 20,
            height: 20
        )
        muteButton.frame = NSRect(x: 0, y: 86, width: 94, height: 28)
    }

    private func configure(snapshot: MainWindowOutputVolumeSnapshot) {
        outputState = snapshot.state
        deviceLabel.stringValue = snapshot.deviceName ?? "没有可用的系统输出"
        let volume = snapshot.state?.volume ?? 0
        let muted = snapshot.state?.isMuted ?? false
        let canSetVolume = snapshot.state?.canSetVolume == true
        let canSetMute = snapshot.state?.canSetMute == true

        slider.doubleValue = Double(volume)
        slider.isEnabled = canSetVolume
        muteButton.isEnabled = canSetMute
        maximumIcon.contentTintColor = canSetVolume ? .labelColor : .disabledControlTextColor
        minimumIcon.contentTintColor = canSetVolume ? .labelColor : .disabledControlTextColor
        updateInteractivePresentation(volume: volume, muted: muted)
    }

    @objc private func changeVolume() {
        guard let outputState, outputState.canSetVolume else { return }
        let volume = Float(slider.doubleValue)
        let shouldUnmute = volume > 0 && outputState.isMuted && outputState.canSetMute
        let muted = shouldUnmute ? false : outputState.isMuted
        self.outputState = OutputVolumeState(
            volume: volume,
            isMuted: muted,
            canSetVolume: outputState.canSetVolume,
            canSetMute: outputState.canSetMute
        )
        updateInteractivePresentation(volume: volume, muted: muted)
        onVolumeChange(volume, shouldUnmute)
    }

    @objc private func toggleMute() {
        onToggleMute()
    }

    private func updateInteractivePresentation(volume: Float, muted: Bool) {
        let percentage = Int((volume * 100).rounded())
        valueLabel.stringValue = muted ? "静音" : "\(percentage)%"
        slider.setAccessibilityValue(muted ? "静音" : "\(percentage)%")
        let symbolName = muted ? "speaker.slash.fill" : volumeSymbol(for: volume)
        muteButton.image = systemSymbol(symbolName, pointSize: 15)
        muteButton.title = muted ? "取消静音" : "静音"
        muteButton.contentTintColor = muteButton.isEnabled
            ? .labelColor
            : .disabledControlTextColor
        muteButton.toolTip = muted ? "取消静音" : "静音"
    }

    private func volumeSymbol(for volume: Float) -> String {
        switch volume {
        case ..<0.01: return "speaker.fill"
        case ..<0.34: return "speaker.wave.1.fill"
        case ..<0.67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }

}

private final class MainTrackingSlider: NSSlider {
    var onTrackingChange: ((Bool) -> Void)?

    override func mouseDown(with event: NSEvent) {
        onTrackingChange?(true)
        super.mouseDown(with: event)
        onTrackingChange?(false)
    }
}

private final class MainApplicationModeView: NSView {
    private let control = NSSegmentedControl(
        labels: ["统一控制", "分开控制"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let onModeChange: (ApplicationVolumeControlMode) -> Void

    init(
        mode: ApplicationVolumeControlMode,
        onModeChange: @escaping (ApplicationVolumeControlMode) -> Void
    ) {
        self.onModeChange = onModeChange
        super.init(frame: .zero)

        control.controlSize = .regular
        control.segmentStyle = .rounded
        control.target = self
        control.action = #selector(selectVolumeMode)
        addSubview(control)

        configure(mode: mode)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        control.frame = bounds
    }

    private func configure(mode: ApplicationVolumeControlMode) {
        control.selectedSegment = mode == .unified ? 0 : 1
    }

    @objc private func selectVolumeMode() {
        let mode: ApplicationVolumeControlMode = control.selectedSegment == 0
            ? .unified
            : .separate
        configure(mode: mode)
        onModeChange(mode)
    }

}

private final class MainApplicationVolumeRow: NSView {
    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "")
    private let slider = MainTrackingSlider()
    private let applicationID: String
    private let onVolumeChange: (String, Double) -> Void

    init(
        application: OutputAudioApplication,
        onVolumeChange: @escaping (String, Double) -> Void,
        onTrackingChange: @escaping (Bool) -> Void
    ) {
        applicationID = application.id
        self.onVolumeChange = onVolumeChange
        super.init(frame: .zero)

        let resolvedIcon = application.icon ?? application.bundleURL.flatMap { url in
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        iconView.image = resolvedIcon ?? systemSymbol("square.grid.2x2.fill", pointSize: 17)
        if resolvedIcon == nil {
            iconView.contentTintColor = .secondaryLabelColor
        }
        iconView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iconView)

        nameLabel.stringValue = application.name
        nameLabel.font = MainWindowTypography.primaryRow
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.toolTip = application.name
        addSubview(nameLabel)

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 11.5, weight: .regular)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right
        addSubview(valueLabel)

        slider.minValue = 0
        slider.maxValue = 1
        slider.doubleValue = application.volume
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(changeVolume)
        slider.onTrackingChange = onTrackingChange
        slider.setAccessibilityLabel("\(application.name) 音量")
        addSubview(slider)
        updateValue()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        iconView.frame = NSRect(x: 2, y: 8, width: 28, height: 28)
        nameLabel.frame = NSRect(x: 42, y: 12, width: 156, height: 20)
        valueLabel.frame = NSRect(x: bounds.width - 50, y: 12, width: 48, height: 20)
        slider.frame = NSRect(
            x: 212,
            y: 9,
            width: max(0, valueLabel.frame.minX - 222),
            height: 26
        )
    }

    @objc private func changeVolume() {
        updateValue()
        onVolumeChange(applicationID, slider.doubleValue)
    }

    private func updateValue() {
        let percentage = Int((slider.doubleValue * 100).rounded())
        valueLabel.stringValue = "\(percentage)%"
        slider.setAccessibilityValue("\(percentage)%")
    }
}

private final class MainDeviceSelectionRow: NSView {
    private let iconBackground = NSView()
    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let selectedLabel = NSTextField(labelWithString: "当前")
    private let button = NSButton()
    private let selected: Bool
    private let onSelect: () -> Void

    init(device: MainWindowDeviceSnapshot, onSelect: @escaping () -> Void) {
        selected = device.isSelected
        self.onSelect = onSelect
        super.init(frame: .zero)

        iconBackground.wantsLayer = true
        iconBackground.layer?.cornerRadius = 14
        addSubview(iconBackground)

        iconView.image = systemSymbol(device.symbolName, pointSize: 17)
        iconView.imageScaling = .scaleProportionallyDown
        addSubview(iconView)

        nameLabel.stringValue = device.name
        nameLabel.font = .systemFont(
            ofSize: 13,
            weight: selected ? .semibold : .regular
        )
        nameLabel.lineBreakMode = .byTruncatingTail
        addSubview(nameLabel)

        detailLabel.stringValue = device.detail
        detailLabel.font = MainWindowTypography.secondaryMedium
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.alignment = .right
        detailLabel.lineBreakMode = .byTruncatingTail
        addSubview(detailLabel)

        selectedLabel.font = .systemFont(ofSize: 10.5, weight: .semibold)
        selectedLabel.textColor = .controlAccentColor
        selectedLabel.alignment = .right
        selectedLabel.isHidden = !selected
        addSubview(selectedLabel)

        button.title = ""
        button.isBordered = false
        button.isTransparent = true
        button.target = self
        button.action = #selector(selectDevice)
        button.setAccessibilityLabel("选择 \(device.name)")
        addSubview(button)

        updateColors()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    override func layout() {
        super.layout()
        iconBackground.frame = NSRect(x: 0, y: 8, width: 28, height: 28)
        iconView.frame = iconBackground.frame.insetBy(dx: 6, dy: 6)
        selectedLabel.frame = NSRect(x: bounds.width - 46, y: 13, width: 46, height: 18)
        detailLabel.frame = NSRect(
            x: bounds.width - 232,
            y: 13,
            width: 174,
            height: 20
        )
        nameLabel.frame = NSRect(
            x: 40,
            y: 12,
            width: max(0, detailLabel.frame.minX - 50),
            height: 22
        )
        button.frame = bounds
    }

    @objc private func selectDevice() {
        onSelect()
    }

    private func updateColors() {
        iconBackground.layer?.backgroundColor = selected
            ? NSColor.controlAccentColor.cgColor
            : NSColor.labelColor.withAlphaComponent(0.08).cgColor
        iconView.contentTintColor = selected ? .white : .secondaryLabelColor
    }
}

private final class MainToggleRow: NSView {
    private let titleLabel: NSTextField
    private let detailLabel: NSTextField
    private let toggle = NSSwitch()
    private let onToggle: () -> Void

    init(
        title: String,
        detail: String,
        isOn: Bool,
        onToggle: @escaping () -> Void
    ) {
        titleLabel = NSTextField(labelWithString: title)
        detailLabel = NSTextField(labelWithString: detail)
        self.onToggle = onToggle
        super.init(frame: .zero)

        titleLabel.font = MainWindowTypography.primaryRow
        addSubview(titleLabel)

        detailLabel.font = MainWindowTypography.tertiary
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail
        addSubview(detailLabel)

        toggle.state = isOn ? .on : .off
        toggle.target = self
        toggle.action = #selector(changeToggle)
        toggle.setAccessibilityLabel(title)
        addSubview(toggle)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        toggle.frame = NSRect(x: bounds.width - 44, y: 10, width: 42, height: 24)
        let textWidth = max(0, bounds.width - 66)
        if detailLabel.stringValue.isEmpty {
            titleLabel.frame = NSRect(x: 0, y: 12, width: textWidth, height: 20)
            detailLabel.isHidden = true
        } else {
            titleLabel.frame = NSRect(x: 0, y: 22, width: textWidth, height: 20)
            detailLabel.frame = NSRect(x: 0, y: 4, width: textWidth, height: 17)
            detailLabel.isHidden = false
        }
    }

    @objc private func changeToggle() {
        onToggle()
    }

}

private final class MainInfoRow: NSView {
    private let label: NSTextField

    init(text: String) {
        label = NSTextField(labelWithString: text)
        super.init(frame: .zero)
        label.font = MainWindowTypography.secondary
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        label.frame = bounds.insetBy(dx: 0, dy: 7)
    }
}

private final class InlineStatusView: NSView {
    private let iconView = NSImageView()
    private let label: NSTextField

    init(message: String) {
        label = NSTextField(labelWithString: message)
        super.init(frame: .zero)
        iconView.image = systemSymbol("info.circle.fill", pointSize: 14)
        iconView.contentTintColor = .controlAccentColor
        addSubview(iconView)
        label.font = MainWindowTypography.secondaryMedium
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        iconView.frame = NSRect(x: 0, y: 5, width: 18, height: 18)
        label.frame = NSRect(x: 26, y: 4, width: bounds.width - 26, height: 20)
    }
}

private final class SegmentedInputLevelMeter: NSView {
    private let segmentCount = 36
    private var normalizedValue: Double = 0

    var doubleValue: Double {
        get { normalizedValue }
        set {
            let finiteValue = newValue.isFinite ? newValue : 0
            let clampedValue = max(0, min(1, finiteValue))
            let oldActiveCount = activeSegmentCount
            normalizedValue = clampedValue
            if activeSegmentCount != oldActiveCount {
                needsDisplay = true
            }
        }
    }

    private var activeSegmentCount: Int {
        SegmentedInputLevelPresentation.activeSegmentCount(
            for: normalizedValue,
            segmentCount: segmentCount
        )
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.progressIndicator)
        setAccessibilityLabel("实时输入电平")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard bounds.width > 0, bounds.height > 0 else { return }

        let gap: CGFloat = 5
        let availableWidth = bounds.width - (CGFloat(segmentCount - 1) * gap)
        let segmentWidth = min(
            7,
            max(2, floor(availableWidth / CGFloat(segmentCount)))
        )
        let totalWidth = (CGFloat(segmentCount) * segmentWidth) +
            (CGFloat(segmentCount - 1) * gap)
        let startX = floor((bounds.width - totalWidth) / 2)
        let segmentHeight = min(34, bounds.height)
        let segmentY = floor((bounds.height - segmentHeight) / 2)
        let activeCount = activeSegmentCount

        for index in 0..<segmentCount {
            let rect = NSRect(
                x: startX + CGFloat(index) * (segmentWidth + gap),
                y: segmentY,
                width: segmentWidth,
                height: segmentHeight
            )
            let path = NSBezierPath(
                roundedRect: rect,
                xRadius: min(2.5, segmentWidth / 2),
                yRadius: min(2.5, segmentWidth / 2)
            )
            let color = index < activeCount
                ? NSColor.systemBlue
                : NSColor.labelColor.withAlphaComponent(0.18)
            color.setFill()
            path.fill()
        }
    }
}

private final class MainWindowMicrophoneTestView: NSView {
    private let titleLabel = NSTextField(labelWithString: "声音测试")
    private let deviceCard = FlatSectionView(frame: .zero)
    private let deviceIconBackground = NSView()
    private let deviceIcon = NSImageView()
    private let deviceNameLabel = NSTextField(labelWithString: "")
    private let deviceDetailLabel = NSTextField(labelWithString: "")
    private let inputSourceButton = NSPopUpButton(frame: .zero, pullsDown: true)
    private let meterCard = FlatSectionView(frame: .zero)
    private let meterTitleLabel = NSTextField(labelWithString: "实时输入电平")
    private let meter = SegmentedInputLevelMeter()
    private let percentageLabel = NSTextField(labelWithString: "0%")
    private let decibelLabel = NSTextField(labelWithString: "-60.0 dBFS")
    private let stateLabel = NSTextField(labelWithString: "")
    private let primaryButton = NSButton(title: "启动测试", target: nil, action: nil)
    private let privacyButton = NSButton(title: "麦克风权限…", target: nil, action: nil)
    private let bottomSeparator = SemanticSeparatorView()
    private let onSelectInput: (String) -> Void
    private let onStart: () -> Void
    private let onStop: () -> Void
    private let onOpenPrivacy: () -> Void
    private var inputDevices: [MainWindowDeviceSnapshot]
    private var phase: MainWindowMicrophoneTestPhase = .idle

    init(
        inputDevices: [MainWindowDeviceSnapshot],
        snapshot: MainWindowMicrophoneTestSnapshot,
        onSelectInput: @escaping (String) -> Void,
        onStart: @escaping () -> Void,
        onStop: @escaping () -> Void,
        onOpenPrivacy: @escaping () -> Void
    ) {
        self.inputDevices = inputDevices
        self.onSelectInput = onSelectInput
        self.onStart = onStart
        self.onStop = onStop
        self.onOpenPrivacy = onOpenPrivacy
        super.init(frame: .zero)

        titleLabel.font = MainWindowTypography.sectionTitle
        addSubview(titleLabel)

        addSubview(deviceCard)

        deviceIconBackground.wantsLayer = true
        deviceIconBackground.layer?.cornerRadius = 22
        deviceCard.addSubview(deviceIconBackground)
        deviceIcon.imageScaling = .scaleProportionallyDown
        deviceCard.addSubview(deviceIcon)

        deviceNameLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        deviceNameLabel.lineBreakMode = .byTruncatingTail
        deviceCard.addSubview(deviceNameLabel)

        deviceDetailLabel.font = MainWindowTypography.secondary
        deviceDetailLabel.textColor = .secondaryLabelColor
        deviceDetailLabel.lineBreakMode = .byTruncatingTail
        deviceCard.addSubview(deviceDetailLabel)

        inputSourceButton.controlSize = .regular
        inputSourceButton.font = MainWindowTypography.secondaryMedium
        inputSourceButton.target = self
        inputSourceButton.action = #selector(selectInputSource)
        inputSourceButton.setAccessibilityLabel("切换系统输入源")
        deviceCard.addSubview(inputSourceButton)

        addSubview(meterCard)
        meterCard.showsBottomSeparator = false

        meterTitleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        meterTitleLabel.alignment = .left
        meterTitleLabel.lineBreakMode = .byTruncatingTail
        meterCard.addSubview(meterTitleLabel)

        meter.doubleValue = 0
        meterCard.addSubview(meter)

        percentageLabel.font = .monospacedDigitSystemFont(ofSize: 23, weight: .semibold)
        percentageLabel.alignment = .right
        percentageLabel.toolTip = "相对电平"
        percentageLabel.setAccessibilityLabel("相对电平百分比")
        meterCard.addSubview(percentageLabel)

        decibelLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        decibelLabel.textColor = .secondaryLabelColor
        decibelLabel.alignment = .right
        decibelLabel.toolTip = "模拟 dBFS"
        decibelLabel.setAccessibilityLabel("模拟分贝")
        meterCard.addSubview(decibelLabel)

        stateLabel.font = MainWindowTypography.secondaryMedium
        stateLabel.textColor = .secondaryLabelColor
        stateLabel.alignment = .left
        stateLabel.lineBreakMode = .byTruncatingTail
        meterCard.addSubview(stateLabel)

        primaryButton.bezelStyle = .rounded
        primaryButton.keyEquivalent = "\r"
        primaryButton.target = self
        primaryButton.action = #selector(activatePrimaryButton)
        meterCard.addSubview(primaryButton)

        privacyButton.bezelStyle = .rounded
        privacyButton.target = self
        privacyButton.action = #selector(openPrivacy)
        meterCard.addSubview(privacyButton)

        addSubview(bottomSeparator)

        updateColors()
        update(inputDevices: inputDevices, snapshot: snapshot)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    override func layout() {
        super.layout()
        let pageWidth = min(620, max(0, bounds.width))
        let pageX = max(0, floor((bounds.width - pageWidth) / 2))
        titleLabel.frame = NSRect(
            x: pageX,
            y: bounds.height - 34,
            width: pageWidth,
            height: 26
        )

        deviceCard.frame = NSRect(
            x: pageX,
            y: titleLabel.frame.minY - 112,
            width: pageWidth,
            height: 96
        )
        deviceIconBackground.frame = NSRect(x: 18, y: 26, width: 44, height: 44)
        deviceIcon.frame = deviceIconBackground.frame.insetBy(dx: 10, dy: 10)
        inputSourceButton.frame = NSRect(
            x: max(218, deviceCard.bounds.width - 178),
            y: 31,
            width: 158,
            height: 32
        )
        let deviceTextWidth = max(0, inputSourceButton.frame.minX - 90)
        deviceNameLabel.frame = NSRect(x: 78, y: 22, width: deviceTextWidth, height: 22)
        deviceDetailLabel.frame = NSRect(x: 78, y: 50, width: deviceTextWidth, height: 19)

        let meterHeight = min(200, max(184, deviceCard.frame.minY - 30))
        meterCard.frame = NSRect(
            x: pageX,
            y: max(0, deviceCard.frame.minY - meterHeight - 18),
            width: pageWidth,
            height: meterHeight
        )
        bottomSeparator.frame = NSRect(x: pageX, y: 0, width: pageWidth, height: 1)
        layoutMeterCard(height: meterHeight)
    }

    func update(
        inputDevices: [MainWindowDeviceSnapshot],
        snapshot: MainWindowMicrophoneTestSnapshot
    ) {
        self.inputDevices = inputDevices
        phase = snapshot.phase
        configureInputSourceButton(selectedUID: snapshot.device?.uid)
        if let device = snapshot.device {
            deviceNameLabel.stringValue = device.name
            deviceDetailLabel.stringValue = device.detail
            deviceIcon.image = systemSymbol(device.symbolName, pointSize: 21)
        } else {
            deviceNameLabel.stringValue = "未找到输入设备"
            deviceDetailLabel.stringValue = "请检查麦克风连接"
            deviceIcon.image = systemSymbol("mic.slash.fill", pointSize: 21)
        }

        switch snapshot.phase {
        case .idle:
            stateLabel.stringValue = "选择输入源后点击启动测试"
            stateLabel.textColor = .secondaryLabelColor
            primaryButton.title = "启动测试"
            setLevel(.silence)
        case .preparing:
            stateLabel.stringValue = "正在连接当前系统输入…"
            stateLabel.textColor = .secondaryLabelColor
            primaryButton.title = "停止测试"
            setLevel(.silence)
        case .testing:
            stateLabel.stringValue = "正在接收声音，请说话"
            stateLabel.textColor = .systemBlue
            primaryButton.title = "停止测试"
        case .failed(let message):
            stateLabel.stringValue = message
            stateLabel.textColor = .systemRed
            primaryButton.title = "重新测试"
            setLevel(.silence)
        }
        primaryButton.isEnabled = snapshot.device != nil || isFailed(snapshot.phase)
        updatePhaseVisibility()
        needsLayout = true
    }

    func pushLevel(_ level: MicrophoneAudioLevel) {
        guard phase == .testing else { return }
        setLevel(level)
    }

    @objc private func activatePrimaryButton() {
        switch phase {
        case .preparing, .testing:
            onStop()
        case .idle, .failed:
            onStart()
        }
    }

    @objc private func openPrivacy() {
        onOpenPrivacy()
    }

    @objc private func selectInputSource() {
        guard let uid = inputSourceButton.selectedItem?.representedObject as? String else {
            inputSourceButton.selectItem(at: 0)
            return
        }
        inputSourceButton.selectItem(at: 0)
        onSelectInput(uid)
    }

    private func configureInputSourceButton(selectedUID: String?) {
        inputSourceButton.removeAllItems()
        inputSourceButton.addItem(withTitle: "切换输入源")
        inputSourceButton.item(at: 0)?.image = systemSymbol(
            "arrow.triangle.2.circlepath",
            pointSize: 13
        )
        for device in inputDevices {
            inputSourceButton.addItem(withTitle: device.name)
            guard let item = inputSourceButton.lastItem else { continue }
            item.representedObject = device.uid
            item.state = device.uid == selectedUID ? .on : .off
            item.image = systemSymbol(device.symbolName, pointSize: 13)
            item.toolTip = device.detail
        }
        inputSourceButton.selectItem(at: 0)
        inputSourceButton.isEnabled = !inputDevices.isEmpty
        inputSourceButton.toolTip = inputDevices.isEmpty
            ? "当前没有可用的系统输入"
            : "选择要测试的系统输入源"
    }

    private func layoutMeterCard(height: CGFloat) {
        let cardWidth = meterCard.bounds.width
        let horizontalInset: CGFloat = 36
        let contentWidth = max(0, cardWidth - horizontalInset * 2)
        let primaryButtonWidth: CGFloat = 132
        let centeredButtonX = max(horizontalInset, (cardWidth - primaryButtonWidth) / 2)
        let decibelWidth: CGFloat = min(132, max(112, contentWidth * 0.25))
        let percentageWidth: CGFloat = min(96, max(78, contentWidth * 0.18))
        let metricGap: CGFloat = 14
        let titleWidth = max(
            0,
            contentWidth - percentageWidth - decibelWidth - metricGap * 2
        )
        meterTitleLabel.frame = NSRect(
            x: horizontalInset,
            y: 23,
            width: titleWidth,
            height: 22
        )
        percentageLabel.frame = NSRect(
            x: meterTitleLabel.frame.maxX + metricGap,
            y: 16,
            width: percentageWidth,
            height: 34
        )
        decibelLabel.frame = NSRect(
            x: cardWidth - horizontalInset - decibelWidth,
            y: 25,
            width: decibelWidth,
            height: 20
        )

        switch phase {
        case .idle:
            let buttonY = max(66, min(height - 48, floor((height - 36) / 2)))
            stateLabel.frame = NSRect(
                x: horizontalInset,
                y: buttonY + 42,
                width: contentWidth,
                height: 20
            )
            primaryButton.frame = NSRect(
                x: centeredButtonX,
                y: buttonY,
                width: primaryButtonWidth,
                height: 36
            )
        case .failed:
            let footerY: CGFloat = 136
            let retryButtonWidth: CGFloat = 112
            let privacyButtonWidth: CGFloat = 132
            let buttonGap: CGFloat = 10
            let totalButtonWidth = retryButtonWidth + buttonGap + privacyButtonWidth
            let buttonStartX = max(
                horizontalInset,
                cardWidth - horizontalInset - totalButtonWidth
            )
            stateLabel.frame = NSRect(
                x: horizontalInset,
                y: footerY + 6,
                width: max(0, buttonStartX - horizontalInset - 16),
                height: 20
            )
            primaryButton.frame = NSRect(
                x: buttonStartX,
                y: footerY,
                width: retryButtonWidth,
                height: 32
            )
            privacyButton.frame = NSRect(
                x: primaryButton.frame.maxX + buttonGap,
                y: footerY,
                width: privacyButtonWidth,
                height: 32
            )
        case .preparing, .testing:
            meter.frame = NSRect(
                x: horizontalInset,
                y: 68,
                width: contentWidth,
                height: 44
            )
            primaryButton.frame = NSRect(
                x: max(horizontalInset, cardWidth - horizontalInset - primaryButtonWidth),
                y: 136,
                width: primaryButtonWidth,
                height: 32
            )
            stateLabel.frame = NSRect(
                x: horizontalInset,
                y: 142,
                width: max(0, primaryButton.frame.minX - horizontalInset - 16),
                height: 20
            )
        }
    }

    private func updatePhaseVisibility() {
        let showsLiveData: Bool
        switch phase {
        case .preparing, .testing:
            showsLiveData = true
        case .idle, .failed:
            showsLiveData = false
        }
        meter.isHidden = !showsLiveData
        percentageLabel.isHidden = !showsLiveData
        decibelLabel.isHidden = !showsLiveData
        stateLabel.isHidden = phase == .idle
        privacyButton.isHidden = !isFailed(phase)
    }

    private func setLevel(_ level: MicrophoneAudioLevel) {
        let normalizedLevel = InputLevelPresentation.directLevel(for: level)
        meter.doubleValue = normalizedLevel
        let percentage = Int((normalizedLevel * 100).rounded())
        percentageLabel.stringValue = "\(percentage)%"
        decibelLabel.stringValue = String(format: "%.1f dBFS", level.decibelsFS)
        meter.setAccessibilityValue("\(percentage)%，\(decibelLabel.stringValue)")
    }

    private func isFailed(_ phase: MainWindowMicrophoneTestPhase) -> Bool {
        if case .failed = phase { return true }
        return false
    }

    private func updateColors() {
        deviceIconBackground.layer?.backgroundColor = NSColor.systemBlue.cgColor
        deviceIcon.contentTintColor = .white
    }
}

private final class AboutMacSoundControlView: NSView {
    private let sectionTitleLabel = NSTextField(labelWithString: "关于")
    private let appIconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "MacSoundControl")
    private let versionLabel = NSTextField(labelWithString: "")
    private let informationPanel = FlatSectionView(frame: .zero)
    private let localProcessingRow = AboutDetailRow(
        title: "本地运行",
        detail: "麦克风与应用音频仅在当前 Mac 的内存中实时处理。"
    )
    private let compatibilityRow = AboutDetailRow(
        title: "系统要求",
        detail: "基础功能支持 macOS 14+，分应用音量支持 macOS 15+。"
    )
    private let openSourceRow = AboutDetailRow(
        title: "开源计划",
        detail: "github.com/RoperYoung/MacSoundControl",
        detailURL: URL(string: "https://github.com/RoperYoung/MacSoundControl")
    )
    private let firstSeparator = SemanticSeparatorView()
    private let secondSeparator = SemanticSeparatorView()
    private let noticesButton = NSButton(title: "查看第三方许可", target: nil, action: nil)
    private let onOpenThirdPartyNotices: () -> Void

    init(versionText: String, onOpenThirdPartyNotices: @escaping () -> Void) {
        self.onOpenThirdPartyNotices = onOpenThirdPartyNotices
        super.init(frame: .zero)

        sectionTitleLabel.font = MainWindowTypography.sectionTitle
        addSubview(sectionTitleLabel)

        appIconView.image = NSApp.applicationIconImage
        appIconView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(appIconView)

        nameLabel.font = .systemFont(ofSize: 24, weight: .bold)
        nameLabel.alignment = .center
        addSubview(nameLabel)

        versionLabel.font = MainWindowTypography.secondary
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.alignment = .center
        addSubview(versionLabel)

        addSubview(informationPanel)
        informationPanel.showsBottomSeparator = false
        informationPanel.addSubview(localProcessingRow)
        informationPanel.addSubview(compatibilityRow)
        informationPanel.addSubview(openSourceRow)
        informationPanel.addSubview(firstSeparator)
        informationPanel.addSubview(secondSeparator)

        noticesButton.bezelStyle = .rounded
        noticesButton.target = self
        noticesButton.action = #selector(openNotices)
        addSubview(noticesButton)

        update(versionText: versionText)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        sectionTitleLabel.frame = NSRect(
            x: 0,
            y: bounds.height - 34,
            width: bounds.width,
            height: 26
        )
        appIconView.frame = NSRect(
            x: (bounds.width - 72) / 2,
            y: sectionTitleLabel.frame.minY - 88,
            width: 72,
            height: 72
        )
        nameLabel.frame = NSRect(
            x: 0,
            y: appIconView.frame.minY - 40,
            width: bounds.width,
            height: 32
        )
        versionLabel.frame = NSRect(x: 0, y: nameLabel.frame.minY - 23, width: bounds.width, height: 18)

        let panelWidth = min(580, max(0, bounds.width - 40))
        let panelHeight: CGFloat = 168
        informationPanel.frame = NSRect(
            x: (bounds.width - panelWidth) / 2,
            y: versionLabel.frame.minY - panelHeight - 20,
            width: panelWidth,
            height: panelHeight
        )
        let rowWidth = max(0, panelWidth - 36)
        localProcessingRow.frame = NSRect(x: 18, y: 8, width: rowWidth, height: 50)
        firstSeparator.frame = NSRect(x: 18, y: 58, width: rowWidth, height: 1)
        compatibilityRow.frame = NSRect(x: 18, y: 59, width: rowWidth, height: 50)
        secondSeparator.frame = NSRect(x: 18, y: 109, width: rowWidth, height: 1)
        openSourceRow.frame = NSRect(x: 18, y: 110, width: rowWidth, height: 50)

        noticesButton.frame = NSRect(
            x: (bounds.width - 152) / 2,
            y: informationPanel.frame.minY - 50,
            width: 152,
            height: 32
        )
    }

    func update(versionText: String) {
        versionLabel.stringValue = versionText
    }

    @objc private func openNotices() {
        onOpenThirdPartyNotices()
    }
}

private final class AboutDetailRow: NSView {
    override var isFlipped: Bool { true }

    private let titleLabel: NSTextField
    private let detailLabel: NSTextField

    init(title: String, detail: String, detailURL: URL? = nil) {
        titleLabel = NSTextField(labelWithString: title)
        detailLabel = NSTextField(labelWithString: detail)
        super.init(frame: .zero)

        titleLabel.font = .systemFont(ofSize: 12.5, weight: .semibold)
        addSubview(titleLabel)

        let detailFont = NSFont.systemFont(ofSize: 12.5, weight: .regular)
        detailLabel.font = detailFont
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.maximumNumberOfLines = 1
        detailLabel.toolTip = detailURL?.absoluteString ?? detail
        if let detailURL {
            let linkedDetail = NSMutableAttributedString(string: detail)
            linkedDetail.addAttributes(
                [
                    .font: detailFont,
                    .foregroundColor: NSColor.linkColor,
                    .link: detailURL,
                ],
                range: NSRange(location: 0, length: linkedDetail.length)
            )
            detailLabel.attributedStringValue = linkedDetail
            detailLabel.isSelectable = true
            detailLabel.allowsEditingTextAttributes = true
        }
        addSubview(detailLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let titleWidth: CGFloat = 112
        titleLabel.frame = NSRect(x: 0, y: 14, width: titleWidth, height: 21)
        detailLabel.frame = NSRect(
            x: titleWidth + 18,
            y: 14,
            width: max(0, bounds.width - titleWidth - 18),
            height: 21
        )
    }
}

private final class ClosureButton: NSButton {
    private let closure: () -> Void

    init(title: String, action: @escaping () -> Void) {
        closure = action
        super.init(frame: .zero)
        self.title = title
        target = self
        self.action = #selector(activate)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func activate() {
        closure()
    }
}

private func makeLabel(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.font = font
    label.textColor = color
    label.lineBreakMode = .byTruncatingTail
    return label
}

private func systemSymbol(_ name: String, pointSize: CGFloat) -> NSImage? {
    let image = NSImage(
        systemSymbolName: name,
        accessibilityDescription: nil
    )?.withSymbolConfiguration(
        NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
    )
    image?.isTemplate = true
    return image
}
