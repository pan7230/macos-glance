import Cocoa
import ServiceManagement

/// MangoDisk 风格的卡片：标题 + 大数值 + 细进度条 + 副标题。
final class MetricCard: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "")
    private let subLabel = NSTextField(labelWithString: "")
    private let bar = BarView()
    private let hasBar: Bool
    let tint: NSColor

    init(title: String, tint: NSColor, hasBar: Bool = true) {
        self.tint = tint
        self.hasBar = hasBar
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.borderWidth = 0

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 24, weight: .semibold)
        valueLabel.textColor = .labelColor
        valueLabel.alignment = .right

        subLabel.font = .systemFont(ofSize: 10.5)
        subLabel.textColor = .tertiaryLabelColor

        bar.tint = tint
        bar.isHidden = !hasBar

        addSubview(titleLabel); addSubview(valueLabel); addSubview(subLabel); addSubview(bar)
    }

    required init?(coder: NSCoder) { fatalError() }

    func set(value: String, sub: String = "", progress: Double = -1) {
        valueLabel.stringValue = value
        subLabel.stringValue = sub
        if hasBar { bar.value = max(0, min(1, progress)) }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        let pad: CGFloat = 14
        titleLabel.frame = NSRect(x: pad, y: h - 30, width: w - 140, height: 18)
        valueLabel.sizeToFit()
        valueLabel.frame = NSRect(x: w - pad - valueLabel.frame.width, y: h - 36,
                                  width: valueLabel.frame.width, height: 30)
        if hasBar {
            bar.frame = NSRect(x: pad, y: 26, width: w - 2 * pad, height: 4)
            subLabel.frame = NSRect(x: pad, y: 8, width: w - 2 * pad, height: 14)
        } else {
            subLabel.frame = NSRect(x: pad, y: 12, width: w - 2 * pad, height: 14)
        }
    }
}

final class PanelViewController: NSViewController {

    var onToggleBarItem: ((BarItem, Bool) -> Void)?
    var onQuit: (() -> Void)?
    var onToggleLogin: ((Bool) -> Void)?
    var onSizeChange: ((NSSize) -> Void)?

    private enum Tab: String, CaseIterable {
        case overview = "概览", cpu = "CPU", gpu = "GPU", mem = "内存", disk = "磁盘", net = "网络"
    }
    private var currentTab: Tab = .overview

    // 卡片
    private let cpuCard = MetricCard(title: "CPU 利用率", tint: .systemOrange)
    private let cpuTempCard = MetricCard(title: "CPU 温度", tint: .systemOrange)
    private let gpuCard = MetricCard(title: "GPU 利用率", tint: .systemTeal)
    private let gpuTempCard = MetricCard(title: "GPU 温度", tint: .systemTeal)
    private let memCard = MetricCard(title: "内存占用", tint: .systemGreen)
    private let memGBCard = MetricCard(title: "内存容量", tint: .systemGreen, hasBar: false)
    private let diskCard = MetricCard(title: "磁盘已用", tint: .systemBlue)
    private let diskTempCard = MetricCard(title: "磁盘温度", tint: .systemBlue)
    private let diskIOCard = MetricCard(title: "磁盘读写", tint: .systemBlue, hasBar: false)
    private let netCard = MetricCard(title: "网络速率", tint: .systemPurple, hasBar: false)

    private let segmented = NSSegmentedControl(labels: Tab.allCases.map { $0.rawValue },
                                               trackingMode: .selectOne, target: nil,
                                               action: #selector(tabChanged(_:)))
    private let pagesContainer = NSView()
    private let uptimeLabel = NSTextField(labelWithString: "")
    private var checkboxes: [BarItem: NSButton] = [:]
    private let loginCheck = NSButton(checkboxWithTitle: "开机自启", target: nil, action: nil)

    private let width: CGFloat = 330
    private var cardHeight: CGFloat = 92
    private(set) var preferredSize = NSSize(width: 330, height: 420)
    private var latest: Snapshot?
    private var footer: NSView?

    override func loadView() {
        view = NSView(frame: NSRect(origin: .zero, size: preferredSize))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        selectTab(.overview)
    }

    // MARK: 构建界面（全部用 frame 布局，避免 Auto Layout 相对约束死锁）

    private func buildUI() {
        // 分段标签页
        segmented.font = .systemFont(ofSize: 11.5, weight: .medium)
        segmented.controlSize = .small
        segmented.selectedSegment = 0
        segmented.target = self
        // 让分段控件占满宽度
        let segW = width - 32
        segmented.setWidth(segW / CGFloat(Tab.allCases.count), forSegment: 0)
        for i in 1..<Tab.allCases.count { segmented.setWidth(segW / CGFloat(Tab.allCases.count), forSegment: i) }
        segmented.frame = NSRect(x: 16, y: 0, width: segW, height: 24)
        view.addSubview(segmented)

        pagesContainer.frame = NSRect(x: 16, y: 0, width: width - 32, height: 300)
        view.addSubview(pagesContainer)
    }

    @objc private func tabChanged(_ sender: NSSegmentedControl) {
        let all = Tab.allCases
        guard sender.selectedSegment < all.count else { return }
        selectTab(all[sender.selectedSegment])
    }

    private func selectTab(_ tab: Tab) {
        currentTab = tab
        // 清掉旧页面
        pagesContainer.subviews.forEach { $0.removeFromSuperview() }

        switch tab {
        case .overview:
            let stack = cardStack([cpuCard, memCard, netCard, cpuTempCard, diskTempCard])
            pagesContainer.addSubview(stack)
        case .cpu:
            pagesContainer.addSubview(cardStack([cpuCard, cpuTempCard]))
        case .gpu:
            pagesContainer.addSubview(cardStack([gpuCard, gpuTempCard]))
        case .mem:
            pagesContainer.addSubview(cardStack([memCard, memGBCard]))
        case .disk:
            pagesContainer.addSubview(cardStack([diskCard, diskTempCard, diskIOCard]))
        case .net:
            pagesContainer.addSubview(cardStack([netCard]))
        }

        layoutForCurrentTab()
        if let snap = latest { apply(snap) }
    }

    private func cardStack(_ cards: [MetricCard]) -> NSView {
        let container = NSView(frame: pagesContainer.bounds)
        let gap: CGFloat = 10
        let h = cardHeight
        for (i, card) in cards.enumerated() {
            card.frame = NSRect(x: 0, y: container.frame.height - CGFloat(i) * (h + gap) - h,
                                width: container.frame.width, height: h)
            container.addSubview(card)
        }
        return container
    }

    private func layoutForCurrentTab() {
        let cardCount: Int
        switch currentTab {
        case .overview: cardCount = 5
        case .cpu, .gpu, .mem: cardCount = 2
        case .disk: cardCount = 3
        case .net: cardCount = 1
        }
        let gap: CGFloat = 10
        let pagesH = CGFloat(cardCount) * cardHeight + CGFloat(max(0, cardCount - 1)) * gap
        let footerH: CGFloat = 62

        segmented.frame = NSRect(x: 16, y: 0, width: width - 32, height: 24)
        pagesContainer.frame = NSRect(x: 16, y: 0, width: width - 32, height: pagesH)

        // 底栏：菜单栏显示开关 + 开机自启 + 退出
        footer?.removeFromSuperview()
        let newFooter = NSView(frame: NSRect(x: 0, y: 0, width: width, height: footerH))
        footer = newFooter
        let footer = newFooter

        let sep = NSView(frame: NSRect(x: 16, y: footerH - 1, width: width - 32, height: 1))
        sep.wantsLayer = true; sep.layer?.backgroundColor = NSColor.separatorColor.cgColor
        footer.addSubview(sep)

        let line1 = NSTextField(labelWithString: "菜单栏显示")
        line1.font = .systemFont(ofSize: 10.5, weight: .medium)
        line1.textColor = .tertiaryLabelColor
        line1.frame = NSRect(x: 16, y: footerH - 20, width: 80, height: 14)
        footer.addSubview(line1)

        // 开关网格 4×2，放在最右；这里用精简文字开关
        let grid = NSGridView(frame: NSRect(x: 16, y: 6, width: width - 90, height: 34))
        grid.rowSpacing = 2; grid.columnSpacing = 6
        for row in 0..<2 {
            var cells: [NSView] = []
            for col in 0..<4 {
                let idx = row * 4 + col
                let item = BarItem.allCases[idx]
                let box = NSButton(checkboxWithTitle: item.label, target: self,
                                   action: #selector(toggleBarItem(_:)))
                box.font = .systemFont(ofSize: 10)
                box.controlSize = .mini
                box.state = Settings.shared.barItems.contains(item) ? .on : .off
                checkboxes[item] = box
                cells.append(box)
            }
            grid.addRow(with: cells)
        }
        footer.addSubview(grid)

        // 开机自启 + 退出（右侧竖排）
        loginCheck.font = .systemFont(ofSize: 10)
        loginCheck.controlSize = .mini
        loginCheck.target = self
        loginCheck.action = #selector(toggleLogin(_:))
        if #available(macOS 13.0, *) {
            loginCheck.state = SMAppService.mainApp.status == .enabled ? .on : .off
        }
        loginCheck.frame = NSRect(x: width - 84, y: 30, width: 76, height: 16)
        footer.addSubview(loginCheck)

        let quit = NSButton(title: "退出", target: self, action: #selector(quit(_:)))
        quit.bezelStyle = .rounded
        quit.controlSize = .mini
        quit.font = .systemFont(ofSize: 10)
        quit.frame = NSRect(x: width - 60, y: 8, width: 48, height: 20)
        footer.addSubview(quit)

        view.addSubview(footer)

        // 重定位 segmented 与 pages：预留底部 footer + 顶部间距
        let topPad: CGFloat = 12
        let totalH = topPad + 24 + 10 + pagesH + 10 + footerH
        segmented.frame = NSRect(x: 16, y: totalH - topPad - 24, width: width - 32, height: 24)
        pagesContainer.frame = NSRect(x: 16, y: footerH + 10, width: width - 32, height: pagesH)
        // 重建页面容器里的卡片坐标（因为 bounds 变了）
        pagesContainer.subviews.forEach { $0.removeFromSuperview() }
        addCardsForCurrentTab()
        view.frame.size = NSSize(width: width, height: totalH)
        preferredSize = view.frame.size
        onSizeChange?(preferredSize)
    }

    private func addCardsForCurrentTab() {
        let cards: [MetricCard]
        switch currentTab {
        case .overview: cards = [cpuCard, memCard, netCard, cpuTempCard, diskTempCard]
        case .cpu: cards = [cpuCard, cpuTempCard]
        case .gpu: cards = [gpuCard, gpuTempCard]
        case .mem: cards = [memCard, memGBCard]
        case .disk: cards = [diskCard, diskTempCard, diskIOCard]
        case .net: cards = [netCard]
        }
        let gap: CGFloat = 10
        for (i, card) in cards.enumerated() {
            card.frame = NSRect(x: 0,
                                y: pagesContainer.frame.height - CGFloat(i) * (cardHeight + gap) - cardHeight,
                                width: pagesContainer.frame.width, height: cardHeight)
            pagesContainer.addSubview(card)
        }
    }

    // MARK: 刷新

    func apply(_ s: Snapshot) {
        latest = s
        let memPct = s.memTotal > 0 ? Double(s.memUsed) / Double(s.memTotal) : 0
        let diskUsed = max(0, s.diskTotal - s.diskFree)
        let diskPct = s.diskTotal > 0 ? Double(diskUsed) / Double(s.diskTotal) : 0
        let cpuTemp = s.cpuTemp.map { String(format: "%.0f °C", $0) } ?? "—"
        let gpuTemp = s.gpuTemp.map { String(format: "%.0f °C", $0) } ?? "—"
        let diskTemp = s.diskTemp.map { String(format: "%.0f °C", $0) } ?? "—"

        cpuCard.set(value: "\(Fmt.percent(s.cpu)) %", sub: "\(s.cpuCores) 核 · Apple Silicon", progress: s.cpu)
        cpuTempCard.set(value: cpuTemp, sub: "CPU 核心最高温", progress: (s.cpuTemp ?? 0) / 100)

        gpuCard.set(value: s.gpuUtil.map { "\(Fmt.percent($0)) %" } ?? "—",
                    sub: "GPU 利用率", progress: s.gpuUtil ?? 0)
        gpuTempCard.set(value: gpuTemp, sub: "tdie 传感器近似", progress: (s.gpuTemp ?? 0) / 100)

        memCard.set(value: "\(Fmt.percent(memPct)) %",
                    sub: "\(Fmt.gb(s.memUsed)) / \(Fmt.gb(s.memTotal)) GB", progress: memPct)
        memGBCard.set(value: "\(Fmt.gb(s.memTotal)) GB", sub: "物理内存总量")

        diskCard.set(value: "\(Fmt.percent(diskPct)) %",
                     sub: "\(Fmt.bytes(Double(diskUsed))) / \(Fmt.bytes(Double(s.diskTotal)))", progress: diskPct)
        diskTempCard.set(value: diskTemp, sub: "NAND 传感器", progress: (s.diskTemp ?? 0) / 100)
        diskIOCard.set(value: "↓\(Fmt.rate(s.diskRead))", sub: "↑ \(Fmt.rate(s.diskWrite))")

        netCard.set(value: "↓\(Fmt.rate(s.netDown))", sub: "↑ \(Fmt.rate(s.netUp))")

        uptimeLabel.stringValue = "已运行 " + Fmt.uptime(s.uptime)
    }

    func syncCheckboxes() {
        for (item, box) in checkboxes {
            box.state = Settings.shared.barItems.contains(item) ? .on : .off
        }
    }

    // MARK: 动作

    @objc private func toggleBarItem(_ sender: NSButton) {
        guard let item = checkboxes.first(where: { $0.value === sender })?.key else { return }
        onToggleBarItem?(item, sender.state == .on)
    }

    @objc private func toggleLogin(_ sender: NSButton) {
        onToggleLogin?(sender.state == .on)
    }

    @objc private func quit(_ sender: Any?) {
        onQuit?()
    }
}
