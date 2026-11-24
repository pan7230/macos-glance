import Cocoa

// MARK: - MangoDisk 风格通用组件

/// 快速创建静态文本
func mdLabel(_ text: String, size: CGFloat = 11, weight: NSFont.Weight = .regular,
             color: NSColor = MDColor.text, align: NSTextAlignment = .left) -> NSTextField {
    let l = NSTextField(labelWithString: text)
    l.font = .systemFont(ofSize: size, weight: weight)
    l.textColor = color
    l.alignment = align
    l.isSelectable = false
    return l
}

/// 白底圆角描边卡片
final class MDCard: NSView {
    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = MDColor.cardBG.cgColor
        layer?.cornerRadius = 12
        layer?.borderWidth = 1
        layer?.borderColor = MDColor.cardBorder.cgColor
        layer?.shadowColor = NSColor.black.withAlphaComponent(0.04).cgColor
        layer?.shadowOpacity = 1
        layer?.shadowRadius = 3
        layer?.shadowOffset = NSSize(width: 0, height: -1)
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// 橙色进度条（MangoDisk 风格）：浅灰轨道 + 橙色填充
final class MDProgressBar: NSView {
    var value: Double = 0 { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 0.5, dy: 0.5)
        let track = NSBezierPath(roundedRect: r, xRadius: r.height/2, yRadius: r.height/2)
        NSColor(calibratedWhite: 0.92, alpha: 1).setFill()
        track.fill()
        let w = max(r.height, r.width * CGFloat(max(0, min(1, value))))
        let fillRect = NSRect(x: r.minX, y: r.minY, width: w, height: r.height)
        let fill = NSBezierPath(roundedRect: fillRect, xRadius: r.height/2, yRadius: r.height/2)
        MDColor.orange.setFill()
        fill.fill()
    }
}

/// 带填充的折线图，支持双色（如网络红↑蓝↓、磁盘读写）
final class MDSparkline: NSView {
    private(set) var series: [[Double]] = []
    var colors: [NSColor] = [MDColor.orange]
    var capacity = 60
    var showFill: Bool = true

    func push(_ values: [Double]) {
        series.append(values)
        if series.count > capacity { series.removeFirst(series.count - capacity) }
        needsDisplay = true
    }
    func reset() { series.removeAll(); needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        guard series.count > 1 else { return }
        let w = bounds.width
        let h = bounds.height
        let pad: CGFloat = 2
        let usableH = h - 2 * pad
        let peak = max(series.flatMap { $0 }.max() ?? 1, 0.0001)
        let step = w / CGFloat(capacity - 1)

        for (idx, color) in colors.enumerated() {
            let values = series.map { idx < $0.count ? $0[idx] : 0 }
            let path = NSBezierPath()
            for (i, v) in values.enumerated() {
                let x = CGFloat(i) * step
                let y = pad + usableH * CGFloat(min(1, max(0, v / peak)))
                if i == 0 { path.move(to: NSPoint(x: x, y: y)) }
                else { path.line(to: NSPoint(x: x, y: y)) }
            }
            if showFill {
                let fill = path.copy() as! NSBezierPath
                fill.line(to: NSPoint(x: CGFloat(values.count - 1) * step, y: 0))
                fill.line(to: NSPoint(x: 0, y: 0))
                fill.close()
                color.withAlphaComponent(0.10).setFill()
                fill.fill()
            }
            path.lineWidth = 1.6
            path.lineJoinStyle = .round
            color.setStroke()
            path.stroke()
        }
    }
}

/// 进程列表中的一行：图标 + 名称 + 数值
final class MDProcessRow: NSView {
    let iconView = NSImageView()
    let nameLabel = mdLabel("", size: 11.5, weight: .medium)
    let detailLabel = mdLabel("", size: 10, color: MDColor.subText)
    let valueLabel = mdLabel("", size: 11.5, weight: .semibold, align: .right)
    private let underline = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iconView)
        addSubview(nameLabel)
        addSubview(detailLabel)
        addSubview(valueLabel)
        underline.wantsLayer = true
        underline.layer?.backgroundColor = MDColor.cardBorder.cgColor
        addSubview(underline)
    }
    required init?(coder: NSCoder) { fatalError() }

    func set(name: String, detail: String = "", value: String, icon: NSImage?) {
        nameLabel.stringValue = name
        detailLabel.stringValue = detail
        valueLabel.stringValue = value
        iconView.image = icon ?? NSWorkspace.shared.icon(forFile: "")
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        iconView.frame = NSRect(x: 0, y: (h-26)/2, width: 26, height: 26)
        let valueW: CGFloat = 72
        valueLabel.frame = NSRect(x: bounds.width - valueW, y: (h-16)/2, width: valueW, height: 16)
        let nameX: CGFloat = 32
        nameLabel.frame = NSRect(x: nameX, y: h/2 + 1, width: bounds.width - nameX - valueW - 4, height: 14)
        detailLabel.frame = NSRect(x: nameX, y: h/2 - 13, width: bounds.width - nameX - valueW - 4, height: 12)
        underline.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 1)
    }
}

/// 自定义标签栏：橙色文字 + 下划线
final class MDTabBar: NSView {
    var onSelect: ((Int) -> Void)?
    private var buttons: [NSButton] = []
    private let underline = NSView()
    private(set) var selectedIndex = 0
    private let tabTitles: [String]

    init(titles: [String]) {
        self.tabTitles = titles
        super.init(frame: .zero)
        underline.wantsLayer = true
        underline.layer?.backgroundColor = MDColor.orange.cgColor
        for (i, title) in titles.enumerated() {
            let b = NSButton(title: title, target: self, action: #selector(click(_:)))
            b.bezelStyle = .inline
            b.isBordered = false
            b.tag = i
            b.font = .systemFont(ofSize: 12, weight: .medium)
            b.contentTintColor = MDColor.subText
            b.frame = .zero
            addSubview(b)
            buttons.append(b)
        }
        addSubview(underline)
    }
    required init?(coder: NSCoder) { fatalError() }

    func select(_ index: Int) {
        guard index >= 0, index < buttons.count else { return }
        selectedIndex = index
        for (i, b) in buttons.enumerated() {
            b.contentTintColor = i == index ? MDColor.orange : MDColor.subText
            b.font = .systemFont(ofSize: 12, weight: i == index ? .semibold : .medium)
        }
        needsLayout = true
    }

    @objc private func click(_ sender: NSButton) {
        select(sender.tag)
        onSelect?(sender.tag)
    }

    override func layout() {
        super.layout()
        let count = buttons.count
        guard count > 0 else { return }
        let w = bounds.width / CGFloat(count)
        for (i, b) in buttons.enumerated() {
            b.frame = NSRect(x: w * CGFloat(i), y: 0, width: w, height: bounds.height - 3)
        }
        let uw: CGFloat = 26
        let ux = w * CGFloat(selectedIndex) + (w - uw) / 2
        underline.frame = NSRect(x: ux, y: 0, width: uw, height: 2.5)
    }
}

/// 彩色小圆点
final class MDColoredDot: NSView {
    var color: NSColor = MDColor.green { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1)).fill()
    }
}
