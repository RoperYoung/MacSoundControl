import AppKit
import Foundation

private func capture(view: NSView, to path: String) throws {
    view.layoutSubtreeIfNeeded()
    view.displayIfNeeded()
    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
        throw NSError(domain: "InterfaceVisualProbe", code: 1)
    }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "InterfaceVisualProbe", code: 2)
    }
    try png.write(to: URL(fileURLWithPath: path), options: .atomic)
}

private func capture(window: NSWindow, to path: String) throws {
    window.layoutIfNeeded()
    window.displayIfNeeded()
    guard let frameView = window.contentView?.superview else {
        throw NSError(domain: "InterfaceVisualProbe", code: 3)
    }
    try capture(view: frameView, to: path)
}

private func runLoop(for seconds: TimeInterval) {
    RunLoop.current.run(until: Date().addingTimeInterval(seconds))
}

private func firstAudioScrollView(in view: NSView) -> NSScrollView? {
    if let scrollView = view as? NSScrollView,
       !(scrollView.documentView is NSOutlineView) {
        return scrollView
    }
    for subview in view.subviews {
        if let scrollView = firstAudioScrollView(in: subview) {
            return scrollView
        }
    }
    return nil
}

private func firstOutlineView(in view: NSView) -> NSOutlineView? {
    if let outlineView = view as? NSOutlineView {
        return outlineView
    }
    for subview in view.subviews {
        if let outlineView = firstOutlineView(in: subview) {
            return outlineView
        }
    }
    return nil
}

private func firstTextField(
    with text: String,
    in view: NSView
) -> NSTextField? {
    if let textField = view as? NSTextField,
       textField.stringValue == text {
        return textField
    }
    for subview in view.subviews {
        if let textField = firstTextField(with: text, in: subview) {
            return textField
        }
    }
    return nil
}

private func selectedSidebarTitle(in view: NSView) -> String? {
    guard let outlineView = firstOutlineView(in: view),
          outlineView.selectedRow >= 0,
          let cell = outlineView.view(
              atColumn: 0,
              row: outlineView.selectedRow,
              makeIfNecessary: false
          ) as? NSTableCellView else {
        return nil
    }
    return cell.textField?.stringValue
}

private func makeDeviceMenuPreview() -> NSWindow {
    let width: CGFloat = 460
    let height: CGFloat = 570
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: width, height: height),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    window.isOpaque = false
    window.backgroundColor = .clear

    let material = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: height))
    material.material = .menu
    material.blendingMode = .behindWindow
    material.state = .active
    material.wantsLayer = true
    material.layer?.cornerRadius = 12
    window.contentView = material

    var top = height - 12

    func addHeader(_ title: String) {
        top -= 28
        let header = MenuSectionHeaderView(
            frame: NSRect(x: 0, y: top, width: width, height: 28),
            title: title
        )
        material.addSubview(header)
    }

    func addDevice(
        _ name: String,
        detail: String,
        symbol: String,
        selected: Bool = false
    ) {
        top -= 42
        let row = PersistentMenuActionView(
            frame: NSRect(x: 0, y: top, width: width, height: 42),
            title: name,
            isSelected: selected,
            style: .device(symbolName: symbol, detail: detail)
        )
        material.addSubview(row)
    }

    func addSeparator() {
        top -= 9
        let separator = NSBox(
            frame: NSRect(x: 16, y: top + 4, width: width - 32, height: 1)
        )
        separator.boxType = .separator
        material.addSubview(separator)
    }

    func addSelection(_ title: String, selected: Bool) {
        top -= 30
        let row = PersistentMenuActionView(
            frame: NSRect(x: 0, y: top, width: width, height: 30),
            title: title,
            isSelected: selected
        )
        material.addSubview(row)
    }

    addHeader("选择系统输出")
    addDevice("DJI Mic Mini 2S TX-8450E8", detail: "蓝牙", symbol: "headphones")
    addDevice("MacBook Pro 扬声器", detail: "内建", symbol: "laptopcomputer")
    addDevice("MCHOSE V9 Turbo+", detail: "USB", symbol: "headphones", selected: true)
    addDevice("Mi monitor", detail: "HDMI", symbol: "display")
    addDevice("Background Music", detail: "虚拟", symbol: "waveform")
    addSeparator()
    addHeader("选择系统输入")
    addDevice("“Neo's iPhone 17 Pro”的麦克风", detail: "连续互通（有线）", symbol: "iphone")
    addDevice("DJI Mic Mini 2S TX-8450E8", detail: "蓝牙", symbol: "headphones", selected: true)
    addDevice("MacBook Pro 麦克风", detail: "内建", symbol: "laptopcomputer")
    addDevice("Studio USB Microphone", detail: "USB", symbol: "mic.fill")
    addSeparator()
    addSelection("开启麦克风常驻", selected: true)
    addSelection("展示虚拟设备", selected: false)
    addSelection("开机自动启动", selected: true)

    return window
}

enum InterfaceVisualProbe {
    static func main() throws {
        guard CommandLine.arguments.count == 6 else {
            fputs(
                "用法：InterfaceVisualProbe <设备菜单 PNG> <概览顶部 PNG> <概览底部 PNG> <输入测试 PNG> <关于 PNG>\n",
                stderr
            )
            exit(2)
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        if let icon = NSImage(contentsOfFile: "Assets/AppIcon.png") {
            app.applicationIconImage = icon
        }

        let inputDevices = [
            MainWindowDeviceSnapshot(
                uid: "iphone",
                name: "“Neo's iPhone 17 Pro”的麦克风",
                detail: "连续互通（有线） · 48 kHz",
                symbolName: "iphone",
                isSelected: false
            ),
            MainWindowDeviceSnapshot(
                uid: "dji",
                name: "DJI Mic Mini 2S TX-8450E8",
                detail: "蓝牙 · 16 kHz",
                symbolName: "headphones",
                isSelected: false
            ),
            MainWindowDeviceSnapshot(
                uid: "builtin-input",
                name: "MacBook Pro 麦克风",
                detail: "内建 · 48 kHz",
                symbolName: "laptopcomputer",
                isSelected: false
            ),
            MainWindowDeviceSnapshot(
                uid: "mchose-input",
                name: "MCHOSE V9 Turbo+",
                detail: "USB · 48 kHz",
                symbolName: "headphones",
                isSelected: true
            ),
        ]
        let outputDevices = [
            MainWindowDeviceSnapshot(
                uid: "dji-output",
                name: "DJI Mic Mini 2S TX-8450E8",
                detail: "蓝牙 · 48 kHz",
                symbolName: "headphones",
                isSelected: false
            ),
            MainWindowDeviceSnapshot(
                uid: "builtin-output",
                name: "MacBook Pro 扬声器",
                detail: "内建 · 48 kHz",
                symbolName: "laptopcomputer",
                isSelected: false
            ),
            MainWindowDeviceSnapshot(
                uid: "mchose",
                name: "MCHOSE V9 Turbo+",
                detail: "USB · 48 kHz",
                symbolName: "headphones",
                isSelected: true
            ),
        ]

        func appIcon(_ path: String) -> NSImage? {
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            return NSWorkspace.shared.icon(forFile: path)
        }

        func application(
            id: String,
            name: String,
            path: String
        ) -> OutputAudioApplication {
            OutputAudioApplication(
                id: id,
                bundleID: id,
                name: name,
                bundleURL: URL(fileURLWithPath: path),
                icon: appIcon(path),
                audioObjectIDs: [],
                volume: 1
            )
        }

        let applications = [
            application(id: "cn.bbdc.BBDC", name: "不背单词", path: "/Applications/不背单词.app"),
            application(id: "com.alibaba.DingTalkMac", name: "钉钉", path: "/Applications/DingTalk.app"),
            application(id: "com.netease.163music", name: "网易云音乐", path: "/Applications/网易云音乐.app"),
            application(id: "com.tencent.xinWeChat", name: "微信", path: "/Applications/WeChat.app"),
            application(id: "com.openai.chat", name: "ChatGPT", path: "/Applications/ChatGPT.app"),
            application(id: "com.openai.chat.helper", name: "ChatGPT", path: "/Applications/ChatGPT.app"),
            application(id: "com.microsoft.edgemac", name: "Microsoft Edge", path: "/Applications/Microsoft Edge.app"),
            application(id: "notion.id", name: "Notion", path: "/Applications/Notion.app"),
            application(id: "com.oppo.connect", name: "OPPO 互联", path: "/Applications/OPPO 互联.app"),
            application(id: "com.todesk.mac", name: "ToDesk", path: "/Applications/ToDesk.app"),
        ]

        func makeSnapshot(
            testPhase: MainWindowMicrophoneTestPhase
        ) -> MainWindowSnapshot {
            MainWindowSnapshot(
                inputDevices: inputDevices,
                outputDevices: outputDevices,
                outputVolume: MainWindowOutputVolumeSnapshot(
                    deviceName: "MCHOSE V9 Turbo+",
                    state: OutputVolumeState(
                        volume: 1,
                        isMuted: false,
                        canSetVolume: true,
                        canSetMute: true
                    )
                ),
                applicationVolumeMode: .separate,
                applicationVolumeSupportState: .ready,
                applications: applications,
                keepAliveEnabled: true,
                virtualDevicesVisible: true,
                launchAtLoginEnabled: true,
                launchAtLoginRequiresApproval: false,
                canReconnectInput: true,
                microphonePermissionDenied: false,
                microphoneTest: MainWindowMicrophoneTestSnapshot(
                    device: inputDevices[3],
                    phase: testPhase
                ),
                statusMessage: "麦克风常驻已启动",
                versionText: "版本 2.3（41）"
            )
        }

        let snapshot = makeSnapshot(testPhase: .idle)

        let devicePreviewWindow = makeDeviceMenuPreview()
        devicePreviewWindow.orderFront(nil)
        runLoop(for: 0.2)
        try capture(
            view: devicePreviewWindow.contentView!,
            to: CommandLine.arguments[1]
        )

        var automaticStartCount = 0
        let mainWindow = MainWindowController(
            snapshot: snapshot,
            actions: .previewActions {
                automaticStartCount += 1
            }
        )
        mainWindow.window?.setContentSize(NSSize(width: 960, height: 700))
        mainWindow.present(destination: .outputVolume)
        if let window = mainWindow.window {
            var frame = window.frame
            frame.size = NSSize(width: 844, height: 698)
            window.setFrame(frame, display: true)
        }
        runLoop(for: 0.25)
        guard let window = mainWindow.window,
              let splitController = window.contentViewController as? NSSplitViewController,
              splitController.splitViewItems.count == 2,
              splitController.splitViewItems[0].behavior == .sidebar else {
            fputs("主窗口没有使用原生 NSSplitViewController 侧栏\n", stderr)
            exit(1)
        }
        let toolbarIdentifiers = window.toolbar?.items.map(\.itemIdentifier) ?? []
        guard toolbarIdentifiers.contains(.toggleSidebar),
              toolbarIdentifiers.contains(.sidebarTrackingSeparator) else {
            fputs("主窗口缺少系统侧栏工具栏控件：\(toolbarIdentifiers)\n", stderr)
            exit(1)
        }
        guard let initialSidebarFrame = splitController.splitViewItems.first?.viewController.view.frame else {
            fputs("找不到原生侧栏分栏\n", stderr)
            exit(1)
        }
        guard let sidebarMaterial = splitController.splitViewItems[0]
            .viewController.view as? NSVisualEffectView,
              sidebarMaterial.material == .sidebar,
              sidebarMaterial.blendingMode == .withinWindow else {
            fputs("侧栏没有使用窗口内混合的原生 sidebar 材质\n", stderr)
            exit(1)
        }
        guard sidebarMaterial.subviews.contains(where: {
            $0.identifier?.rawValue == "MainSidebarNeutralOverlay"
        }) else {
            fputs("侧栏缺少动态系统底色的中性校准层\n", stderr)
            exit(1)
        }
        let resizedPosition = initialSidebarFrame.width < 220
            ? initialSidebarFrame.width + 28
            : initialSidebarFrame.width - 28
        splitController.splitView.setPosition(resizedPosition, ofDividerAt: 0)
        splitController.splitView.layoutSubtreeIfNeeded()
        runLoop(for: 0.08)
        guard let resizedSidebarFrame = splitController.splitViewItems.first?.viewController.view.frame,
              abs(resizedSidebarFrame.width - initialSidebarFrame.width) > 12 else {
            let currentWidth = splitController.splitViewItems.first?.viewController.view.frame.width ?? -1
            let frames = splitController.splitViewItems.map {
                "\($0.behavior.rawValue):\($0.viewController.view.frame)"
            }
            let splitFrames = splitController.splitView.subviews.map {
                "\(type(of: $0)):\($0.frame)"
            }
            fputs(
                "原生侧栏分隔线不能拖动调宽：\(initialSidebarFrame.width) -> \(currentWidth)，目标 \(resizedPosition)，项目 \(frames)，子视图 \(splitFrames)\n",
                stderr
            )
            exit(1)
        }
        splitController.splitView.setPosition(initialSidebarFrame.width, ofDividerAt: 0)
        splitController.splitView.layoutSubtreeIfNeeded()

        let sidebarItem = splitController.splitViewItems[0]
        splitController.toggleSidebar(nil)
        runLoop(for: 0.35)
        guard sidebarItem.isCollapsed else {
            fputs("系统侧栏按钮不能收起侧栏\n", stderr)
            exit(1)
        }
        splitController.toggleSidebar(nil)
        runLoop(for: 0.35)
        guard !sidebarItem.isCollapsed else {
            fputs("系统侧栏按钮不能恢复侧栏\n", stderr)
            exit(1)
        }

        try capture(window: window, to: CommandLine.arguments[2])

        guard let scrollView = firstAudioScrollView(in: window.contentView!) else {
            fputs("找不到主窗口滚动视图\n", stderr)
            exit(1)
        }
        guard let scrollContainer = scrollView.superview,
              abs(scrollView.frame.minX - scrollContainer.bounds.minX) < 0.5,
              abs(scrollView.frame.maxX - scrollContainer.bounds.maxX) < 0.5,
              abs(scrollView.frame.maxY - scrollContainer.bounds.maxY) < 0.5 else {
            fputs("右侧滚动视图没有贴合内容窗格边缘\n", stderr)
            exit(1)
        }
        guard let documentView = scrollView.documentView,
              let outputTitle = firstTextField(
                  with: "系统输出音量",
                  in: documentView
              ) else {
            fputs("找不到系统输出音量标题\n", stderr)
            exit(1)
        }
        let titleFrame = outputTitle.convert(outputTitle.bounds, to: documentView)
        guard abs(titleFrame.minX - 24) < 0.5,
              abs((outputTitle.font?.pointSize ?? 0) - 14) < 0.1 else {
            fputs(
                "右侧内容起点或标题字号不符合规范：x=\(titleFrame.minX)，font=\(outputTitle.font?.pointSize ?? -1)\n",
                stderr
            )
            exit(1)
        }
        var anchorOrigins: [CGFloat] = []
        for destination in MainWindowDestination.allCases {
            mainWindow.present(destination: destination)
            runLoop(for: 0.32)
            anchorOrigins.append(scrollView.contentView.bounds.minY)
        }
        for index in 1..<anchorOrigins.count {
            guard anchorOrigins[index] > anchorOrigins[index - 1] + 20 else {
                fputs("侧边栏锚点没有按页面顺序递增：\(anchorOrigins)\n", stderr)
                exit(1)
            }
        }
        for (index, destination) in MainWindowDestination.allCases.enumerated() {
            scrollView.contentView.scroll(
                to: NSPoint(x: 0, y: anchorOrigins[index])
            )
            scrollView.reflectScrolledClipView(scrollView.contentView)
            runLoop(for: 0.05)
            let selectedTitle = selectedSidebarTitle(
                in: window.contentView!
            )
            guard selectedTitle == destination.title else {
                fputs(
                    "手动滚动后侧栏未同步：预期 \(destination.title)，实际 \(selectedTitle ?? "无")\n",
                    stderr
                )
                exit(1)
            }
        }

        mainWindow.present(destination: .residencyAndStartup)
        runLoop(for: 0.32)
        try capture(window: window, to: CommandLine.arguments[3])

        mainWindow.present(destination: .inputTest)
        runLoop(for: 0.32)
        guard automaticStartCount == 0 else {
            fputs("输入测试页面不应自动启动测试\n", stderr)
            exit(1)
        }
        try capture(window: window, to: CommandLine.arguments[4])

        mainWindow.update(snapshot: makeSnapshot(testPhase: .testing))
        mainWindow.pushMicrophoneLevel(
            MicrophoneAudioLevel(rootMeanSquare: pow(10, -12.0 / 20.0))
        )
        runLoop(for: 0.1)
        let activeInputTestURL = URL(fileURLWithPath: CommandLine.arguments[4])
            .deletingPathExtension()
            .appendingPathExtension("active.png")
        try capture(window: window, to: activeInputTestURL.path)

        mainWindow.showAbout()
        runLoop(for: 0.32)
        guard let documentView = scrollView.documentView else {
            fputs("About 验证时找不到主窗口文档\n", stderr)
            exit(1)
        }
        let aboutPairs = [
            ("本地运行", "麦克风与应用音频仅在当前 Mac 的内存中实时处理。"),
            ("系统要求", "基础功能支持 macOS 14+，分应用音量支持 macOS 15+。"),
            ("开源计划", "github.com/RoperYoung/MacSoundControl"),
        ]
        for (title, detail) in aboutPairs {
            guard let titleLabel = firstTextField(with: title, in: documentView),
                  let detailLabel = firstTextField(with: detail, in: documentView) else {
                fputs("About 信息行缺少文字：\(title) / \(detail)\n", stderr)
                exit(1)
            }
            let titleFrame = titleLabel.convert(titleLabel.bounds, to: documentView)
            let detailFrame = detailLabel.convert(detailLabel.bounds, to: documentView)
            guard abs(titleFrame.minY - detailFrame.minY) < 0.5,
                  abs(titleFrame.height - detailFrame.height) < 0.5 else {
                fputs(
                    "About 信息行没有基线对齐：\(titleFrame) / \(detailFrame)\n",
                    stderr
                )
                exit(1)
            }
        }
        guard let repositoryLabel = firstTextField(
            with: "github.com/RoperYoung/MacSoundControl",
            in: documentView
        ),
              repositoryLabel.attributedStringValue.attribute(
                  .link,
                  at: 0,
                  effectiveRange: nil
              ) as? URL == URL(string: "https://github.com/RoperYoung/MacSoundControl") else {
            fputs("About 缺少可点击的 GitHub 仓库链接\n", stderr)
            exit(1)
        }
        try capture(window: window, to: CommandLine.arguments[5])

        print("InterfaceVisualProbe: passed")
    }
}
