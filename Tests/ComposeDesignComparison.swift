import AppKit
import Foundation

@main
enum ComposeDesignComparison {
    static func main() throws {
        guard CommandLine.arguments.count == 8 else {
            fputs(
                "用法：ComposeDesignComparison <旧概览顶部> <旧概览底部> <旧输入测试> <新概览顶部> <新概览底部> <新输入测试> <输出>\n",
                stderr
            )
            exit(2)
        }

        let images = CommandLine.arguments[1...6].compactMap {
            NSImage(contentsOfFile: $0)
        }
        guard images.count == 6 else {
            fputs("无法读取对比图片\n", stderr)
            exit(1)
        }

        let size = NSSize(width: 1320, height: 1500)
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            fputs("无法创建对比画布\n", stderr)
            exit(1)
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor(calibratedWhite: 0.94, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

        func drawTitle(_ title: String, x: CGFloat, y: CGFloat) {
            (title as NSString).draw(
                at: NSPoint(x: x, y: y),
                withAttributes: [
                    .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
                    .foregroundColor: NSColor.labelColor,
                ]
            )
        }

        drawTitle("Build 36 · 分页式顶部", x: 20, y: 1464)
        drawTitle("Build 37 · 单页锚点顶部", x: 680, y: 1464)
        drawTitle("Build 36 · 分页式底部", x: 20, y: 984)
        drawTitle("Build 37 · 常驻与启动锚点", x: 680, y: 984)
        drawTitle("Build 36 · 独立声音测试页", x: 20, y: 504)
        drawTitle("Build 37 · 单页声音测试锚点", x: 680, y: 504)

        images[0].draw(
            in: NSRect(x: 20, y: 1008, width: 620, height: 452),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        images[1].draw(
            in: NSRect(x: 20, y: 528, width: 620, height: 452),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        images[2].draw(
            in: NSRect(x: 20, y: 48, width: 620, height: 452),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        images[3].draw(
            in: NSRect(x: 680, y: 1008, width: 620, height: 452),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        images[4].draw(
            in: NSRect(x: 680, y: 528, width: 620, height: 452),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        images[5].draw(
            in: NSRect(x: 680, y: 48, width: 620, height: 452),
            from: .zero,
            operation: .copy,
            fraction: 1
        )

        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            fputs("无法编码对比图片\n", stderr)
            exit(1)
        }
        try png.write(
            to: URL(fileURLWithPath: CommandLine.arguments[7]),
            options: .atomic
        )
        print("ComposeDesignComparison: passed")
    }
}
