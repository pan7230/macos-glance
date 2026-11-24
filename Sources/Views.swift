import Cocoa

// MARK: - 数值格式化

enum Fmt {

    static func bytes(_ v: Double) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = max(0, v)
        var i = 0
        while value >= 1024, i < units.count - 1 { value /= 1024; i += 1 }
        let decimals: Int = (i == 0 || value >= 100) ? 0 : 1
        return String(format: "%.\(decimals)f %@", value, units[i])
    }

    static func rate(_ v: Double) -> String {
        bytes(v) + "/s"
    }

    /// 菜单栏用的紧凑速率：33 KB/s / 1.2 MB/s（MangoDisk 风格）
    static func compactRate(_ v: Double) -> String {
        let units = ["B", "KB", "MB", "GB"]
        var value = max(0, v)
        var i = 0
        while value >= 1024, i < units.count - 1 { value /= 1024; i += 1 }
        if value < 0.05 { return "0 B/s" }
        let decimals: Int = (i == 0 || value >= 100) ? 0 : (value >= 10 ? 0 : 1)
        return String(format: "%.\(decimals)f %@/s", value, units[i])
    }

    static func gb(_ v: UInt64) -> String {
        String(format: "%.1f", Double(v) / 1_073_741_824)
    }

    static func percent(_ v: Double) -> String {
        String(format: "%.0f", max(0, min(1, v)) * 100)
    }

    static func uptime(_ t: TimeInterval) -> String {
        let total = Int(t)
        let d = total / 86400
        let h = (total % 86400) / 3600
        let m = (total % 3600) / 60
        if d > 0 { return "\(d) 天 \(h) 小时" }
        if h > 0 { return "\(h) 小时 \(m) 分" }
        return "\(m) 分"
    }
}

// MARK: - 细进度条

final class BarView: NSView {
    var value: Double = 0 { didSet { needsDisplay = true } }
    var tint: NSColor = .controlAccentColor

    override func draw(_ dirtyRect: NSRect) {
        let h = bounds.height
        let radius = h / 2
        let track = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
        NSColor.quaternaryLabelColor.setFill()
        track.fill()

        let w = bounds.width * CGFloat(max(0, min(1, value)))
        guard w > 0.5 else { return }
        let fillRect = NSRect(x: 0, y: 0, width: max(w, h), height: h)
        let fill = NSBezierPath(roundedRect: fillRect, xRadius: radius, yRadius: radius)
        tint.withAlphaComponent(0.9).setFill()
        fill.fill()
    }
}

// MARK: - 迷你走势图

final class SparkView: NSView {
    private(set) var down: [Double] = []
    private(set) var up: [Double] = []
    var tint: NSColor = .systemPurple
    var tint2: NSColor = .systemTeal
    let capacity = 60

    func push(down d: Double, up u: Double) {
        down.append(d); up.append(u)
        if down.count > capacity { down.removeFirst(down.count - capacity) }
        if up.count > capacity { up.removeFirst(up.count - capacity) }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard down.count > 1 else { return }
        let peak = max(down.max() ?? 1, up.max() ?? 1, 1)
        let w = bounds.width
        let h = bounds.height
        let step = w / CGFloat(capacity - 1)

        func path(_ values: [Double]) -> NSBezierPath {
            let p = NSBezierPath()
            for (i, v) in values.enumerated() {
                let x = CGFloat(i) * step
                let y = h * CGFloat(max(0, min(1, v / peak)))
                if i == 0 { p.move(to: NSPoint(x: x, y: y)) } else { p.line(to: NSPoint(x: x, y: y)) }
            }
            return p
        }

        // 下载流量填充
        let downPath = path(down)
        let fill = downPath.copy() as! NSBezierPath
        fill.line(to: NSPoint(x: CGFloat(down.count - 1) * step, y: 0))
        fill.line(to: NSPoint(x: 0, y: 0))
        fill.close()
        tint.withAlphaComponent(0.18).setFill()
        fill.fill()

        downPath.lineWidth = 1.3
        tint.setStroke()
        downPath.stroke()

        let upPath = path(up)
        upPath.lineWidth = 1.0
        tint2.withAlphaComponent(0.85).setStroke()
        upPath.stroke()
    }
}

// MARK: - 一行指标

final class MetricRow: NSView {

    private let titleLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "")
    private let subLabel = NSTextField(labelWithString: "")
    let bar = BarView()
    let spark = SparkView()

    private let hasBar: Bool
    private let hasSpark: Bool
    private let hasSub: Bool

    var height: CGFloat {
        19 + (hasBar ? 8 : 0) + (hasSpark ? 18 : 0) + (hasSub ? 15 : 0) + 4
    }

    init(title: String, hasBar: Bool = false, hasSpark: Bool = false,
         hasSub: Bool = false, tint: NSColor) {
        self.hasBar = hasBar
        self.hasSpark = hasSpark
        self.hasSub = hasSub
        super.init(frame: .zero)

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 12.5, weight: .semibold)
        valueLabel.textColor = .labelColor
        valueLabel.alignment = .right

        subLabel.font = .systemFont(ofSize: 10.5)
        subLabel.textColor = .tertiaryLabelColor

        bar.tint = tint
        spark.tint = tint

        addSubview(titleLabel)
        addSubview(valueLabel)
        addSubview(bar)
        addSubview(spark)
        addSubview(subLabel)
        bar.isHidden = !hasBar
        spark.isHidden = !hasSpark
        subLabel.isHidden = !hasSub
    }

    required init?(coder: NSCoder) { fatalError() }

    func set(value: String, sub: String? = nil) {
        valueLabel.stringValue = value
        if let sub { subLabel.stringValue = sub }
    }

    override func layout() {
        super.layout()
        let w = bounds.width
        var top = bounds.height

        let vSize = valueLabel.intrinsicContentSize
        valueLabel.frame = NSRect(x: max(0, w - vSize.width), y: top - 17, width: vSize.width, height: 16)
        titleLabel.frame = NSRect(x: 0, y: top - 17, width: max(0, w - vSize.width - 8), height: 16)
        top -= 19

        if hasBar {
            bar.frame = NSRect(x: 0, y: top - 4, width: w, height: 4)
            top -= 8
        }
        if hasSpark {
            spark.frame = NSRect(x: 0, y: top - 16, width: w, height: 16)
            top -= 18
        }
        if hasSub {
            subLabel.frame = NSRect(x: 0, y: top - 13, width: w, height: 13)
            top -= 15
        }
    }
}

// MARK: - 菜单栏标题（用系统原生 attributedTitle，自动适配深浅色）

/// MangoDisk 菜单栏配色：青绿色标签与数值
private let mdTeal = NSColor(calibratedRed: 0.18, green: 0.62, blue: 0.49, alpha: 1.0)
/// MangoDisk 网络配色：上传红、下载蓝
private let mdUploadRed = NSColor(calibratedRed: 0.95, green: 0.26, blue: 0.21, alpha: 1.0)
private let mdDownloadBlue = NSColor(calibratedRed: 0.13, green: 0.48, blue: 0.95, alpha: 1.0)

/// MangoDisk 风格菜单栏项：上行小标签 + 下行数值，青绿色，行高固定。
func makeMetricTitle(label: String, value: String) -> NSAttributedString {
    let labelFont = NSFont.systemFont(ofSize: 7.5, weight: .semibold)
    let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .medium)

    let style = NSMutableParagraphStyle()
    style.alignment = .center
    style.lineSpacing = 0
    style.minimumLineHeight = 9
    style.maximumLineHeight = 9

    let result = NSMutableAttributedString()
    result.append(NSAttributedString(string: label, attributes: [
        .font: labelFont,
        .foregroundColor: mdTeal.withAlphaComponent(0.85),
        .paragraphStyle: style
    ]))
    result.append(NSAttributedString(string: "\n" + value, attributes: [
        .font: valueFont,
        .foregroundColor: mdTeal,
        .paragraphStyle: style
    ]))
    return result
}

/// MangoDisk 网络菜单栏项：上行红色↑上传，下行蓝色↓下载，无文字标签。
func makeNetworkTitle(up: String, down: String) -> NSAttributedString {
    let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)
    let style = NSMutableParagraphStyle()
    style.alignment = .left
    style.lineSpacing = 0
    style.minimumLineHeight = 9
    style.maximumLineHeight = 9

    let result = NSMutableAttributedString()
    result.append(NSAttributedString(string: "↑ \(up)", attributes: [
        .font: font, .foregroundColor: mdUploadRed, .paragraphStyle: style
    ]))
    result.append(NSAttributedString(string: "\n↓ \(down)", attributes: [
        .font: font, .foregroundColor: mdDownloadBlue, .paragraphStyle: style
    ]))
    return result
}

/// 面板里使用的同一套配色
enum MDColor {
    static let teal = mdTeal
    static let orange = NSColor(calibratedRed: 1.0, green: 0.42, blue: 0.03, alpha: 1.0)
    static let orangeSoft = NSColor(calibratedRed: 1.0, green: 0.42, blue: 0.03, alpha: 0.14)
    static let blue = mdDownloadBlue
    static let red = mdUploadRed
    static let green = NSColor(calibratedRed: 0.20, green: 0.65, blue: 0.30, alpha: 1.0)
    static let panelBG = NSColor(calibratedWhite: 0.965, alpha: 1.0)
    static let cardBG = NSColor.white
    static let cardBorder = NSColor(calibratedWhite: 0.89, alpha: 1.0)
    static let text = NSColor(calibratedWhite: 0.13, alpha: 1.0)
    static let subText = NSColor(calibratedWhite: 0.48, alpha: 1.0)
}

// 保留：模板图版本（back-up，当前未使用）

func makeStatusImage(text: String) -> NSImage {
    let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
    let str = NSAttributedString(string: text, attributes: attrs)
    let size = str.size()
    let scale: CGFloat = 2

    let pxW = max(1, ceil(size.width * scale))
    let pxH = max(1, ceil(size.height * scale))
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                     pixelsWide: Int(pxW), pixelsHigh: Int(pxH),
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0) else { return NSImage() }
    rep.size = NSSize(width: size.width, height: size.height)

    NSGraphicsContext.saveGraphicsState()
    if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
        NSGraphicsContext.current = ctx
        str.draw(at: .zero)
        ctx.flushGraphics()
    }
    NSGraphicsContext.restoreGraphicsState()

    let image = NSImage(size: NSSize(width: size.width, height: size.height))
    image.addRepresentation(rep)
    image.isTemplate = true
    return image
}
