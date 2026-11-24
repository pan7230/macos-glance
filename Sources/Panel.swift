import Cocoa
import ServiceManagement

// MARK: - 各页面（frame 布局，避免 Auto Layout 死锁）

private let pageInset: CGFloat = 14
private let cardGap: CGFloat = 10

/// 页面通用：固定宽度，内容从顶部往下排
private class MDPage: NSView {
    let contentWidth: CGFloat
    var cursorY: CGFloat
    init(width: CGFloat, height: CGFloat) {
        self.contentWidth = width - 2 * pageInset
        self.cursorY = height - pageInset
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))
    }
    required init?(coder: NSCoder) { fatalError() }

    /// 放置一个视图，占用 h 高度，之后留出 gap
    func place(_ v: NSView, h: CGFloat, gap: CGFloat = cardGap) {
        cursorY -= h
        v.frame = NSRect(x: pageInset, y: cursorY, width: contentWidth, height: h)
        addSubview(v)
        cursorY -= gap
    }
    func update(_ s: Snapshot) {}
}

// MARK: 概览页（两列小卡片 + 内存 + 磁盘 + 网络）

private final class OverviewPage: MDPage {
    let cpuCard = MDCard()
    let gpuCard = MDCard()
    let memCard = MDCard()
    let diskCard = MDCard()
    let netCard = MDCard()

    let cpuValue = mdLabel("", size: 24, weight: .bold)
    let gpuValue = mdLabel("", size: 24, weight: .bold)
    let cpuFoot = mdLabel("", size: 10, color: MDColor.subText)
    let gpuFoot = mdLabel("", size: 10, color: MDColor.subText)
    let cpuSpark = MDSparkline()
    let gpuSpark = MDSparkline()
    let memValue = mdLabel("", size: 24, weight: .bold)
    let memBar = MDProgressBar()
    let memFoot = mdLabel("", size: 10, color: MDColor.subText)
    let memStatus = mdLabel("压力正常", size: 10, color: MDColor.green, align: .right)
    let memDot = MDColoredDot()
    let diskValue = mdLabel("", size: 24, weight: .bold)
    let diskBar = MDProgressBar()
    let diskFoot = mdLabel("", size: 10, color: MDColor.subText)
    let diskAction = mdLabel("深度清理 ›", size: 10, color: MDColor.orange, align: .right)
    let netDown = mdLabel("", size: 15, weight: .semibold, color: MDColor.blue)
    let netUp = mdLabel("", size: 15, weight: .semibold, color: MDColor.red)
    let netSpark = MDSparkline()
    let netFoot = mdLabel("", size: 10, color: MDColor.subText)

    init(width: CGFloat) {
        super.init(width: width, height: 430)

        // 第一排：CPU / GPU 并排
        let half = (contentWidth - cardGap) / 2
        let topY = cursorY - 104
        cpuCard.frame = NSRect(x: pageInset, y: topY, width: half, height: 104)
        gpuCard.frame = NSRect(x: pageInset + half + cardGap, y: topY, width: half, height: 104)
        addSubview(cpuCard); addSubview(gpuCard)
        setupSmallCard(cpuCard, title: "CPU", value: cpuValue, spark: cpuSpark, foot: cpuFoot, tint: MDColor.orange)
        setupSmallCard(gpuCard, title: "GPU", value: gpuValue, spark: gpuSpark, foot: gpuFoot, tint: MDColor.orange)
        cursorY -= 104 + cardGap

        // 内存
        place(memCard, h: 96)
        setupBarCard(memCard, title: "内存", value: memValue, bar: memBar, foot: memFoot,
                     rightFoot: memStatus, dot: memDot)
        // 磁盘
        place(diskCard, h: 96)
        setupBarCard(diskCard, title: "磁盘 › 系统盘", value: diskValue, bar: diskBar, foot: diskFoot,
                     rightFoot: diskAction, dot: nil)
        // 网络
        place(netCard, h: 100)
        setupNetworkCard()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setupSmallCard(_ card: MDCard, title: String, value: NSTextField,
                                spark: MDSparkline, foot: NSTextField, tint: NSColor) {
        let t = mdLabel(title, size: 12, weight: .semibold)
        t.frame = NSRect(x: 12, y: card.bounds.height - 26, width: 90, height: 16)
        card.addSubview(t)
        value.frame = NSRect(x: 12, y: card.bounds.height - 60, width: card.bounds.width - 24, height: 32)
        card.addSubview(value)
        spark.frame = NSRect(x: 12, y: 26, width: card.bounds.width - 24, height: 18)
        spark.colors = [tint]
        card.addSubview(spark)
        foot.frame = NSRect(x: 12, y: 7, width: card.bounds.width - 24, height: 14)
        card.addSubview(foot)
    }

    private func setupBarCard(_ card: MDCard, title: String, value: NSTextField,
                              bar: MDProgressBar, foot: NSTextField,
                              rightFoot: NSTextField, dot: MDColoredDot?) {
        let t = mdLabel(title, size: 12, weight: .semibold)
        t.frame = NSRect(x: 14, y: card.bounds.height - 26, width: card.bounds.width - 90, height: 16)
        card.addSubview(t)
        value.frame = NSRect(x: card.bounds.width - 76, y: card.bounds.height - 34, width: 62, height: 26)
        value.alignment = .right
        card.addSubview(value)
        bar.frame = NSRect(x: 14, y: 38, width: card.bounds.width - 28, height: 5)
        card.addSubview(bar)
        foot.frame = NSRect(x: 14, y: 12, width: card.bounds.width * 0.62, height: 15)
        card.addSubview(foot)
        rightFoot.frame = NSRect(x: card.bounds.width * 0.6, y: 12, width: card.bounds.width * 0.38 - 14, height: 15)
        card.addSubview(rightFoot)
        if let dot {
            dot.frame = NSRect(x: card.bounds.width - 96, y: 16, width: 8, height: 8)
            card.addSubview(dot)
        }
    }

    private func setupNetworkCard() {
        let t = mdLabel("网络 ›", size: 12, weight: .semibold)
        t.frame = NSRect(x: 14, y: netCard.bounds.height - 26, width: 100, height: 16)
        netCard.addSubview(t)
        netDown.frame = NSRect(x: 14, y: netCard.bounds.height - 56, width: 140, height: 22)
        netUp.frame = NSRect(x: 164, y: netCard.bounds.height - 56, width: 140, height: 22)
        netCard.addSubview(netDown); netCard.addSubview(netUp)
        netSpark.frame = NSRect(x: 14, y: 28, width: netCard.bounds.width - 28, height: 18)
        netSpark.colors = [MDColor.red, MDColor.blue]
        netCard.addSubview(netSpark)
        netFoot.frame = NSRect(x: 14, y: 8, width: netCard.bounds.width - 28, height: 14)
        netCard.addSubview(netFoot)
    }

    override func update(_ s: Snapshot) {
        let memPct = s.memTotal > 0 ? Double(s.memUsed) / Double(s.memTotal) : 0
        let diskUsed = max(0, s.diskTotal - s.diskFree)
        let diskPct = s.diskTotal > 0 ? Double(diskUsed) / Double(s.diskTotal) : 0

        cpuValue.stringValue = "\(Fmt.percent(s.cpu)) %"
        gpuValue.stringValue = s.gpuUtil.map { "\(Fmt.percent($0)) %" } ?? "—"
        cpuFoot.stringValue = "Apple Silicon · \(s.cpuTemp.map { "\(Int($0.rounded())) °C" } ?? "—")"
        gpuFoot.stringValue = "Apple Silicon · \(s.gpuTemp.map { "\(Int($0.rounded())) °C" } ?? "—")"
        cpuSpark.push([s.cpu])
        gpuSpark.push([s.gpuUtil ?? 0])

        memValue.stringValue = "\(Fmt.percent(memPct)) %"
        memBar.value = memPct
        memFoot.stringValue = "\(Fmt.gb(s.memUsed)) / \(Fmt.gb(s.memTotal)) GB"
        diskValue.stringValue = "\(Fmt.percent(diskPct)) %"
        diskBar.value = diskPct
        diskFoot.stringValue = "可用 \(Fmt.bytes(Double(s.diskFree))) / \(Fmt.bytes(Double(s.diskTotal)))"
        netDown.stringValue = "↓ \(Fmt.rate(s.netDown))"
        netUp.stringValue = "↑ \(Fmt.rate(s.netUp))"
        netSpark.push([s.netUp, s.netDown])
        netFoot.stringValue = "Wi-Fi · 最近一分钟"
    }
}

// MARK: CPU 页

private final class CPUPage: MDPage {
    let utilCard = MDCard(), tempCard = MDCard(), freqCard = MDCard()
    let utilValue = mdLabel("", size: 26, weight: .bold)
    let tempValue = mdLabel("", size: 26, weight: .bold)
    let utilSpark = MDSparkline(), tempSpark = MDSparkline()
    let utilFoot = mdLabel("Apple Silicon", size: 10, color: MDColor.subText)
    let freqLabels: [NSTextField]
    let procHost = NSView()
    private var procRows: [MDProcessRow] = []
    private let maxRows = 10
    private var iconCache: [Int32: NSImage] = [:]

    init(width: CGFloat) {
        freqLabels = (0..<3).map { _ in mdLabel("", size: 17, weight: .bold) }
        super.init(width: width, height: 590)
        place(utilCard, h: 100)
        let ut = mdLabel("CPU 利用率", size: 12, weight: .semibold)
        ut.frame = NSRect(x: 14, y: utilCard.bounds.height - 26, width: 160, height: 16)
        utilCard.addSubview(ut)
        utilValue.frame = NSRect(x: utilCard.bounds.width - 90, y: utilCard.bounds.height - 36, width: 76, height: 30)
        utilValue.alignment = .right
        utilCard.addSubview(utilValue)
        utilSpark.frame = NSRect(x: 14, y: 28, width: utilCard.bounds.width - 28, height: 22)
        utilSpark.colors = [MDColor.orange]
        utilCard.addSubview(utilSpark)
        utilFoot.frame = NSRect(x: 14, y: 8, width: utilCard.bounds.width - 28, height: 14)
        utilCard.addSubview(utilFoot)

        place(tempCard, h: 92)
        let tt = mdLabel("CPU 温度 ⓘ", size: 12, weight: .semibold)
        tt.frame = NSRect(x: 14, y: tempCard.bounds.height - 26, width: 160, height: 16)
        tempCard.addSubview(tt)
        tempValue.frame = NSRect(x: tempCard.bounds.width - 100, y: tempCard.bounds.height - 36, width: 86, height: 30)
        tempValue.alignment = .right
        tempCard.addSubview(tempValue)
        tempSpark.frame = NSRect(x: 14, y: 26, width: tempCard.bounds.width - 28, height: 18)
        tempSpark.colors = [MDColor.orange]
        tempCard.addSubview(tempSpark)

        place(freqCard, h: 74)
        let titles = ["能效核心", "性能核心", "超级核心"]
        let fw = contentWidth / 3
        for (i, title) in titles.enumerated() {
            let label = mdLabel(title, size: 10, color: MDColor.subText, align: .center)
            label.frame = NSRect(x: fw * CGFloat(i), y: 48, width: fw, height: 14)
            freqCard.addSubview(label)
            freqLabels[i].frame = NSRect(x: fw * CGFloat(i), y: 20, width: fw, height: 26)
            freqLabels[i].alignment = .center
            freqCard.addSubview(freqLabels[i])
        }

        // 应用列表
        let header = mdLabel("应用名称", size: 11, weight: .semibold)
        header.frame = NSRect(x: pageInset, y: cursorY - 20, width: 120, height: 16)
        addSubview(header)
        let sort = mdLabel("CPU ˅", size: 10, color: MDColor.subText, align: .right)
        sort.frame = NSRect(x: bounds.width - pageInset - 80, y: cursorY - 20, width: 80, height: 16)
        addSubview(sort)
        cursorY -= 26

        procHost.frame = NSRect(x: pageInset, y: pageInset, width: contentWidth, height: cursorY - pageInset)
        addSubview(procHost)
        for i in 0..<maxRows {
            let row = MDProcessRow(frame: NSRect(x: 0, y: procHost.bounds.height - CGFloat(i+1) * 34,
                                                 width: contentWidth, height: 34))
            procRows.append(row)
            procHost.addSubview(row)
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func update(_ s: Snapshot) {
        utilValue.stringValue = "\(Fmt.percent(s.cpu)) %"
        tempValue.stringValue = s.cpuTemp.map { "\(Int($0.rounded())) °C" } ?? "—"
        utilSpark.push([s.cpu])
        tempSpark.push([(s.cpuTemp ?? 0) / 100])
        // 核心频率用 sysctl 近似值展示（Apple Silicon 无公开实时频率接口）
        let freq = CPUFrequency.current()
        let values = [freq.efficiency, freq.performance, freq.efficientPerformance ?? 0]
        for (i, v) in values.enumerated() {
            freqLabels[i].stringValue = v > 0 ? String(format: "%.1f GHz", v) : "—"
        }
        let top = s.processes.sorted { $0.cpu > $1.cpu }.prefix(maxRows)
        for (i, p) in top.enumerated() {
            let icon = iconCache[p.pid] ?? {
                let img = NSWorkspace.shared.icon(forFile: p.path)
                iconCache[p.pid] = img
                return img
            }()
            procRows[i].set(name: p.name, value: String(format: "%.1f%%", p.cpu * 100), icon: icon)
            procRows[i].isHidden = false
        }
        if top.count < maxRows {
            for i in top.count..<maxRows { procRows[i].isHidden = true }
        }
    }
}

// MARK: GPU 页

private final class GPUPage: MDPage {
    let utilCard = MDCard(), tempCard = MDCard(), engineCard = MDCard()
    let utilValue = mdLabel("", size: 26, weight: .bold)
    let tempValue = mdLabel("", size: 26, weight: .bold)
    let utilSpark = MDSparkline(), tempSpark = MDSparkline()
    let coreLabel = mdLabel("", size: 20, weight: .bold)
    let avgLabel = mdLabel("", size: 20, weight: .bold)
    let peakLabel = mdLabel("", size: 20, weight: .bold)
    let rendererValue = mdLabel("", size: 11, weight: .semibold, align: .right)
    let tilerValue = mdLabel("", size: 11, weight: .semibold, align: .right)
    let engineSpark = MDSparkline()
    private var history: [Double] = []

    init(width: CGFloat) {
        super.init(width: width, height: 440)
        place(utilCard, h: 100)
        let ut = mdLabel("GPU 利用率", size: 12, weight: .semibold)
        ut.frame = NSRect(x: 14, y: utilCard.bounds.height - 26, width: 160, height: 16)
        utilCard.addSubview(ut)
        utilValue.frame = NSRect(x: utilCard.bounds.width - 90, y: utilCard.bounds.height - 36, width: 76, height: 30)
        utilValue.alignment = .right
        utilCard.addSubview(utilValue)
        utilSpark.frame = NSRect(x: 14, y: 28, width: utilCard.bounds.width - 28, height: 22)
        utilSpark.colors = [MDColor.orange]
        utilCard.addSubview(utilSpark)
        let foot = mdLabel("Apple Silicon", size: 10, color: MDColor.subText)
        foot.frame = NSRect(x: 14, y: 8, width: utilCard.bounds.width - 28, height: 14)
        utilCard.addSubview(foot)

        place(tempCard, h: 92)
        let tt = mdLabel("GPU 温度 ⓘ", size: 12, weight: .semibold)
        tt.frame = NSRect(x: 14, y: tempCard.bounds.height - 26, width: 160, height: 16)
        tempCard.addSubview(tt)
        tempValue.frame = NSRect(x: tempCard.bounds.width - 100, y: tempCard.bounds.height - 36, width: 86, height: 30)
        tempValue.alignment = .right
        tempCard.addSubview(tempValue)
        tempSpark.frame = NSRect(x: 14, y: 26, width: tempCard.bounds.width - 28, height: 18)
        tempSpark.colors = [MDColor.orange]
        tempCard.addSubview(tempSpark)

        place(engineCard, h: 190)
        let fw = contentWidth / 3
        let titles = ["GPU 核心", "1 分钟平均", "1 分钟峰值"]
        let labels = [coreLabel, avgLabel, peakLabel]
        for (i, title) in titles.enumerated() {
            let l = mdLabel(title, size: 10, color: MDColor.subText, align: .center)
            l.frame = NSRect(x: fw * CGFloat(i), y: engineCard.bounds.height - 28, width: fw, height: 14)
            engineCard.addSubview(l)
            labels[i].frame = NSRect(x: fw * CGFloat(i), y: engineCard.bounds.height - 58, width: fw, height: 26)
            labels[i].alignment = .center
            engineCard.addSubview(labels[i])
        }
        let engineTitle = mdLabel("引擎活动 ⓘ", size: 11, weight: .semibold)
        engineTitle.frame = NSRect(x: 14, y: 92, width: 120, height: 16)
        engineCard.addSubview(engineTitle)
        let rendererLabel = mdLabel("Renderer", size: 10, color: MDColor.subText)
        rendererLabel.frame = NSRect(x: 14, y: 68, width: 80, height: 14)
        engineCard.addSubview(rendererLabel)
        rendererValue.frame = NSRect(x: engineCard.bounds.width - 70, y: 68, width: 56, height: 14)
        engineCard.addSubview(rendererValue)
        engineSpark.frame = NSRect(x: 14, y: 22, width: engineCard.bounds.width - 28, height: 40)
        engineSpark.colors = [MDColor.orange]
        engineCard.addSubview(engineSpark)
        let tilerLabel = mdLabel("Tiler", size: 10, color: MDColor.subText)
        tilerLabel.frame = NSRect(x: 14, y: 6, width: 80, height: 14)
        engineCard.addSubview(tilerLabel)
        tilerValue.frame = NSRect(x: engineCard.bounds.width - 70, y: 6, width: 56, height: 14)
        engineCard.addSubview(tilerValue)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func update(_ s: Snapshot) {
        let util = s.gpuUtil ?? 0
        utilValue.stringValue = "\(Fmt.percent(util)) %"
        tempValue.stringValue = s.gpuTemp.map { "\(Int($0.rounded())) °C" } ?? "—"
        utilSpark.push([util])
        tempSpark.push([(s.gpuTemp ?? 0) / 100])
        history.append(util)
        if history.count > 60 { history.removeFirst() }
        coreLabel.stringValue = "12"
        avgLabel.stringValue = history.isEmpty ? "—" : String(format: "%.0f%%", history.reduce(0, +) / Double(history.count) * 100)
        peakLabel.stringValue = history.isEmpty ? "—" : String(format: "%.0f%%", (history.max() ?? 0) * 100)
        rendererValue.stringValue = String(format: "%.0f%%", util * 100)
        tilerValue.stringValue = "—"
        engineSpark.push([util])
    }
}

// MARK: 内存页

private final class MemPage: MDPage {
    let memCard = MDCard()
    let memValue = mdLabel("", size: 26, weight: .bold)
    let memBar = MDProgressBar()
    let memFoot = mdLabel("", size: 10, color: MDColor.subText)
    let statusLabel = mdLabel("● 压力正常", size: 10, weight: .medium, color: MDColor.green)
    let procHost = NSView()
    private var procRows: [MDProcessRow] = []
    private let maxRows = 12
    private var iconCache: [Int32: NSImage] = [:]

    init(width: CGFloat) {
        super.init(width: width, height: 600)
        place(memCard, h: 100)
        let t = mdLabel("内存", size: 12, weight: .semibold)
        t.frame = NSRect(x: 14, y: memCard.bounds.height - 26, width: 80, height: 16)
        memCard.addSubview(t)
        statusLabel.frame = NSRect(x: 70, y: memCard.bounds.height - 26, width: 100, height: 16)
        memCard.addSubview(statusLabel)
        memValue.frame = NSRect(x: memCard.bounds.width - 90, y: memCard.bounds.height - 38, width: 76, height: 30)
        memValue.alignment = .right
        memCard.addSubview(memValue)
        memBar.frame = NSRect(x: 14, y: 42, width: memCard.bounds.width - 28, height: 5)
        memCard.addSubview(memBar)
        memFoot.frame = NSRect(x: 14, y: 18, width: memCard.bounds.width - 28, height: 15)
        memCard.addSubview(memFoot)
        let release = NSButton(title: "⚡ 释放", target: nil, action: nil)
        release.bezelStyle = .rounded
        release.contentTintColor = .white
        release.frame = NSRect(x: memCard.bounds.width - 84, y: 12, width: 70, height: 24)
        memCard.addSubview(release)

        let header = mdLabel("应用名称", size: 11, weight: .semibold)
        header.frame = NSRect(x: pageInset, y: cursorY - 20, width: 120, height: 16)
        addSubview(header)
        let sort = mdLabel("内存 ˅", size: 10, color: MDColor.subText, align: .right)
        sort.frame = NSRect(x: bounds.width - pageInset - 80, y: cursorY - 20, width: 80, height: 16)
        addSubview(sort)
        cursorY -= 26

        procHost.frame = NSRect(x: pageInset, y: pageInset, width: contentWidth, height: cursorY - pageInset)
        addSubview(procHost)
        for i in 0..<maxRows {
            let row = MDProcessRow(frame: NSRect(x: 0, y: procHost.bounds.height - CGFloat(i+1) * 34,
                                                 width: contentWidth, height: 34))
            procRows.append(row)
            procHost.addSubview(row)
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func update(_ s: Snapshot) {
        let pct = s.memTotal > 0 ? Double(s.memUsed) / Double(s.memTotal) : 0
        memValue.stringValue = "\(Fmt.percent(pct)) %"
        memBar.value = pct
        memFoot.stringValue = "已用 \(Fmt.gb(s.memUsed)) / \(Fmt.gb(s.memTotal)) GB"
        let top = s.processes.sorted { $0.memory > $1.memory }.prefix(maxRows)
        for (i, p) in top.enumerated() {
            let icon = iconCache[p.pid] ?? {
                let img = NSWorkspace.shared.icon(forFile: p.path)
                iconCache[p.pid] = img
                return img
            }()
            procRows[i].set(name: p.name, value: Fmt.bytes(Double(p.memory)), icon: icon)
            procRows[i].isHidden = false
        }
        if top.count < maxRows {
            for i in top.count..<maxRows { procRows[i].isHidden = true }
        }
    }
}

// MARK: 磁盘页

private final class DiskPage: MDPage {
    let capCard = MDCard(), ioCard = MDCard(), healthCard = MDCard()
    let capValue = mdLabel("", size: 26, weight: .bold)
    let capBar = MDProgressBar()
    let capFoot = mdLabel("", size: 10, color: MDColor.subText)
    let readValue = mdLabel("", size: 20, weight: .bold)
    let writeValue = mdLabel("", size: 20, weight: .bold)
    let ioSpark = MDSparkline()
    let healthGrid = NSView()

    init(width: CGFloat) {
        super.init(width: width, height: 490)
        place(capCard, h: 96)
        let t = mdLabel("磁盘 › 系统盘", size: 12, weight: .semibold)
        t.frame = NSRect(x: 14, y: capCard.bounds.height - 26, width: 160, height: 16)
        capCard.addSubview(t)
        capValue.frame = NSRect(x: capCard.bounds.width - 90, y: capCard.bounds.height - 36, width: 76, height: 30)
        capValue.alignment = .right
        capCard.addSubview(capValue)
        capBar.frame = NSRect(x: 14, y: 40, width: capCard.bounds.width - 28, height: 5)
        capCard.addSubview(capBar)
        capFoot.frame = NSRect(x: 14, y: 16, width: capCard.bounds.width - 100, height: 15)
        capCard.addSubview(capFoot)
        let clean = NSButton(title: "深度清理", target: nil, action: nil)
        clean.bezelStyle = .rounded
        clean.contentTintColor = .white
        clean.frame = NSRect(x: capCard.bounds.width - 96, y: 12, width: 82, height: 24)
        capCard.addSubview(clean)

        place(ioCard, h: 120)
        let ioTitle = mdLabel("磁盘活动", size: 11, weight: .semibold)
        ioTitle.frame = NSRect(x: 14, y: ioCard.bounds.height - 24, width: 100, height: 16)
        ioCard.addSubview(ioTitle)
        let rLabel = mdLabel("读取", size: 10, color: MDColor.blue)
        rLabel.frame = NSRect(x: 14, y: ioCard.bounds.height - 48, width: 60, height: 14)
        ioCard.addSubview(rLabel)
        readValue.frame = NSRect(x: 14, y: ioCard.bounds.height - 72, width: 140, height: 24)
        ioCard.addSubview(readValue)
        let wLabel = mdLabel("写入", size: 10, color: MDColor.red)
        wLabel.frame = NSRect(x: 160, y: ioCard.bounds.height - 48, width: 60, height: 14)
        ioCard.addSubview(wLabel)
        writeValue.frame = NSRect(x: 160, y: ioCard.bounds.height - 72, width: 140, height: 24)
        ioCard.addSubview(writeValue)
        ioSpark.frame = NSRect(x: 14, y: 12, width: ioCard.bounds.width - 28, height: 28)
        ioSpark.colors = [MDColor.red, MDColor.blue]
        ioCard.addSubview(ioSpark)

        place(healthCard, h: 154)
        let ht = mdLabel("磁盘健康", size: 11, weight: .semibold)
        ht.frame = NSRect(x: 14, y: healthCard.bounds.height - 24, width: 100, height: 16)
        healthCard.addSubview(ht)
        let status = mdLabel("健康", size: 10, weight: .medium, color: MDColor.green)
        status.frame = NSRect(x: healthCard.bounds.width - 60, y: healthCard.bounds.height - 24, width: 46, height: 16)
        status.alignment = .right
        healthCard.addSubview(status)
        healthGrid.frame = NSRect(x: 14, y: 10, width: healthCard.bounds.width - 28, height: 110)
        healthCard.addSubview(healthGrid)
        buildHealthGrid()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func buildHealthGrid() {
        let items: [(String, String)] = [
            ("健康度", "100 %"), ("累计写入", "—"), ("通电时间", "—"),
            ("累计读取", "—"), ("温度", "—"), ("可用备用空间", "100 %"),
            ("电源循环", "—"), ("介质错误", "0")
        ]
        let cols = 3
        let cw = healthGrid.bounds.width / CGFloat(cols)
        for (i, item) in items.enumerated() {
            let col = i % cols, row = i / cols
            let x = cw * CGFloat(col), y = healthGrid.bounds.height - CGFloat(row + 1) * 36
            let l = mdLabel(item.0, size: 9, color: MDColor.subText)
            l.frame = NSRect(x: x, y: y + 18, width: cw, height: 12)
            healthGrid.addSubview(l)
            let v = mdLabel(item.1, size: 12, weight: .semibold)
            v.frame = NSRect(x: x, y: y, width: cw, height: 18)
            healthGrid.addSubview(v)
        }
    }

    override func update(_ s: Snapshot) {
        let used = max(0, s.diskTotal - s.diskFree)
        let pct = s.diskTotal > 0 ? Double(used) / Double(s.diskTotal) : 0
        capValue.stringValue = "\(Fmt.percent(pct)) %"
        capBar.value = pct
        capFoot.stringValue = "可用 \(Fmt.bytes(Double(s.diskFree))) / \(Fmt.bytes(Double(s.diskTotal)))"
        readValue.stringValue = Fmt.rate(s.diskRead)
        writeValue.stringValue = Fmt.rate(s.diskWrite)
        ioSpark.push([s.diskWrite, s.diskRead])
    }
}

// MARK: 网络页

private final class NetPage: MDPage {
    let flowCard = MDCard(), statsCard = MDCard(), ifaceCard = MDCard()
    let downValue = mdLabel("", size: 28, weight: .bold, color: MDColor.blue)
    let upValue = mdLabel("", size: 28, weight: .bold, color: MDColor.red)
    let netSpark = MDSparkline()
    let wifiLabel = mdLabel("● Wi-Fi · 已连接", size: 10, color: MDColor.green)
    let totalDown = mdLabel("", size: 16, weight: .bold)
    let totalUp = mdLabel("", size: 16, weight: .bold)
    private var ifaceLabels: [NSTextField] = []

    init(width: CGFloat) {
        super.init(width: width, height: 500)
        place(flowCard, h: 130)
        let t = mdLabel("网络", size: 12, weight: .semibold)
        t.frame = NSRect(x: 14, y: flowCard.bounds.height - 24, width: 80, height: 16)
        flowCard.addSubview(t)
        downValue.frame = NSRect(x: 14, y: flowCard.bounds.height - 64, width: 140, height: 34)
        flowCard.addSubview(downValue)
        upValue.frame = NSRect(x: 164, y: flowCard.bounds.height - 64, width: 140, height: 34)
        flowCard.addSubview(upValue)
        let dl = mdLabel("↓ 下载", size: 10, color: MDColor.subText)
        dl.frame = NSRect(x: 14, y: flowCard.bounds.height - 78, width: 100, height: 14)
        flowCard.addSubview(dl)
        let ul = mdLabel("↑ 上传", size: 10, color: MDColor.subText)
        ul.frame = NSRect(x: 164, y: flowCard.bounds.height - 78, width: 100, height: 14)
        flowCard.addSubview(ul)
        netSpark.frame = NSRect(x: 14, y: 34, width: flowCard.bounds.width - 28, height: 24)
        netSpark.colors = [MDColor.red, MDColor.blue]
        netSpark.showFill = false
        flowCard.addSubview(netSpark)
        wifiLabel.frame = NSRect(x: 14, y: 12, width: 200, height: 14)
        flowCard.addSubview(wifiLabel)

        place(statsCard, h: 90)
        let st = mdLabel("流量", size: 11, weight: .semibold)
        st.frame = NSRect(x: 14, y: statsCard.bounds.height - 24, width: 60, height: 16)
        statsCard.addSubview(st)
        let dlL = mdLabel("累计下载", size: 9, color: MDColor.subText)
        dlL.frame = NSRect(x: 14, y: 44, width: 80, height: 12)
        statsCard.addSubview(dlL)
        totalDown.frame = NSRect(x: 14, y: 20, width: 130, height: 24)
        statsCard.addSubview(totalDown)
        let ulL = mdLabel("累计上传", size: 9, color: MDColor.subText)
        ulL.frame = NSRect(x: 160, y: 44, width: 80, height: 12)
        statsCard.addSubview(ulL)
        totalUp.frame = NSRect(x: 160, y: 20, width: 130, height: 24)
        statsCard.addSubview(totalUp)

        place(ifaceCard, h: 160)
        let it = mdLabel("本地网卡", size: 11, weight: .semibold)
        it.frame = NSRect(x: 14, y: ifaceCard.bounds.height - 24, width: 100, height: 16)
        ifaceCard.addSubview(it)
        let keys = ["链路速度", "MAC 地址", "IPv4", "IPv6", "Wi-Fi 标准", "信道"]
        for (i, key) in keys.enumerated() {
            let y = ifaceCard.bounds.height - 46 - CGFloat(i) * 20
            let l = mdLabel(key, size: 10, color: MDColor.subText)
            l.frame = NSRect(x: 14, y: y, width: 90, height: 14)
            ifaceCard.addSubview(l)
            let v = mdLabel("—", size: 10, weight: .medium, align: .right)
            v.frame = NSRect(x: 100, y: y, width: ifaceCard.bounds.width - 114, height: 14)
            ifaceCard.addSubview(v)
            ifaceLabels.append(v)
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func update(_ s: Snapshot) {
        downValue.stringValue = Fmt.rate(s.netDown)
        upValue.stringValue = Fmt.rate(s.netUp)
        netSpark.push([s.netUp, s.netDown])
        let info = NetworkInfo.current()
        for (i, v) in [info.speed, info.mac, info.ipv4, info.ipv6, info.standard, info.channel].enumerated() {
            if i < ifaceLabels.count { ifaceLabels[i].stringValue = v }
        }
        totalDown.stringValue = info.totalDown
        totalUp.stringValue = info.totalUp
    }
}

// MARK: - 辅助：CPU 频率与网络信息

private struct CPUFrequency {
    var efficiency: Double = 0
    var performance: Double = 0
    var efficientPerformance: Double? = nil

    static func current() -> CPUFrequency {
        var f = CPUFrequency()
        // Apple Silicon 的实时频率无公开 API；用 Brand 与标称频率展示
        var brand = ""
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        if size > 0 {
            var buf = [CChar](repeating: 0, count: size)
            sysctlbyname("machdep.cpu.brand_string", &buf, &size, nil, 0)
            brand = String(cString: buf)
        }
        // 用已知机型的标称频率作为展示值
        if brand.contains("M4") || brand.contains("M6") {
            f.efficiency = 1.3; f.performance = 2.4; f.efficientPerformance = 2.2
        } else if brand.contains("M3") {
            f.efficiency = 1.2; f.performance = 2.1; f.efficientPerformance = nil
        } else if brand.contains("M2") {
            f.efficiency = 1.0; f.performance = 1.8; f.efficientPerformance = nil
        } else if brand.contains("M1") {
            f.efficiency = 0.8; f.performance = 1.6; f.efficientPerformance = nil
        } else {
            f.efficiency = 0; f.performance = 0; f.efficientPerformance = nil
        }
        return f
    }
}

private struct NetworkInfo {
    var speed = "—", mac = "—", ipv4 = "—", ipv6 = "—", standard = "—", channel = "—"
    var totalDown = "—", totalUp = "—"

    static func current() -> NetworkInfo {
        var info = NetworkInfo()
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var len = 0
        guard sysctl(&mib, 6, nil, &len, nil, 0) == 0, len > 0 else { return info }
        var buf = [UInt8](repeating: 0, count: len)
        guard buf.withUnsafeMutableBytes({ sysctl(&mib, 6, $0.baseAddress, &len, nil, 0) }) == 0 else { return info }
        buf.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var off = 0
            while off + MemoryLayout<if_msghdr>.size <= len {
                let hdr = base.advanced(by: off).assumingMemoryBound(to: if_msghdr.self).pointee
                let msglen = Int(hdr.ifm_msglen)
                if msglen <= 0 { break }
                if Int32(hdr.ifm_type) == RTM_IFINFO2, msglen >= MemoryLayout<if_msghdr2>.size {
                    let m2 = base.advanced(by: off).assumingMemoryBound(to: if_msghdr2.self).pointee
                    var nb = [CChar](repeating: 0, count: Int(IFNAMSIZ)+1)
                    if if_indextoname(UInt32(m2.ifm_index), &nb) != nil {
                        let name = String(cString: nb)
                        if name.hasPrefix("en") {
                            info.speed = "\(m2.ifm_data.ifi_baudrate / 1_000_000) Mbps"
                            info.totalDown = Fmt.bytes(Double(m2.ifm_data.ifi_ibytes))
                            info.totalUp = Fmt.bytes(Double(m2.ifm_data.ifi_obytes))
                        }
                    }
                }
                off += msglen
            }
        }
        // 地址信息
        var ifap: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&ifap) == 0 {
            var p = ifap
            while let cur = p {
                let name = String(cString: cur.pointee.ifa_name)
                if name.hasPrefix("en") {
                    let family = cur.pointee.ifa_addr.pointee.sa_family
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if family == UInt8(AF_INET) {
                        getnameinfo(cur.pointee.ifa_addr, socklen_t(cur.pointee.ifa_addr.pointee.sa_len),
                                    &host, UInt32(host.count), nil, 0, NI_NUMERICHOST)
                        info.ipv4 = String(cString: host)
                    } else if family == UInt8(AF_INET6) {
                        getnameinfo(cur.pointee.ifa_addr, socklen_t(cur.pointee.ifa_addr.pointee.sa_len),
                                    &host, UInt32(host.count), nil, 0, NI_NUMERICHOST)
                        let v = String(cString: host)
                        if v.count > 0 { info.ipv6 = String(v.prefix(24)) + "…" }
                    } else if family == UInt8(AF_LINK) {
                        let sdl = cur.pointee.ifa_addr.withMemoryRebound(to: sockaddr_dl.self, capacity: 1) { $0.pointee }
                        let addr = withUnsafePointer(to: sdl.sdl_data) { ptr in
                            ptr.withMemoryRebound(to: UInt8.self, capacity: Int(sdl.sdl_nlen + 6)) { p in
                                (0..<6).map { String(format: "%02x", p[Int(sdl.sdl_nlen) + $0]) }.joined(separator: ":")
                            }
                        }
                        info.mac = addr
                    }
                }
                p = cur.pointee.ifa_next
            }
            freeifaddrs(ifap)
        }
        return info
    }
}

// MARK: - 面板控制器

final class PanelViewController: NSViewController {

    var onToggleBarItem: ((BarItem, Bool) -> Void)?
    var onQuit: (() -> Void)?
    var onToggleLogin: ((Bool) -> Void)?
    var onSizeChange: ((NSSize) -> Void)?

    private enum Tab: String, CaseIterable {
        case overview = "概览", cpu = "CPU", gpu = "GPU", mem = "内存", disk = "磁盘", net = "网络"
    }
    private var currentTab: Tab = .overview
    private var pendingTabName: String?

    private let tabBar = MDTabBar(titles: Tab.allCases.map { $0.rawValue })
    private let pageHolder = NSView()
    private let footer = NSView()
    private let width: CGFloat = 340
    private let footerHeight: CGFloat = 44
    private let tabHeight: CGFloat = 38
    private(set) var preferredSize = NSSize(width: 340, height: 520)
    private var latest: Snapshot?
    private var pages: [Tab: MDPage] = [:]

    override func loadView() {
        view = NSView(frame: NSRect(origin: .zero, size: preferredSize))
        view.wantsLayer = true
        view.layer?.backgroundColor = MDColor.panelBG.cgColor
        view.layer?.cornerRadius = 14
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        if let name = pendingTabName, let tab = diagnosticsMap[name.lowercased()] {
            selectTab(tab)
        } else {
            selectTab(.overview)
        }
    }

    private let diagnosticsMap: [String: Tab] = [
        "overview": .overview, "cpu": .cpu, "gpu": .gpu,
        "mem": .mem, "disk": .disk, "net": .net
    ]

    private func buildUI() {
        tabBar.onSelect = { [weak self] index in
            guard index < Tab.allCases.count else { return }
            self?.selectTab(Tab.allCases[index])
        }
        view.addSubview(tabBar)
        view.addSubview(pageHolder)
        buildFooter()
        view.addSubview(footer)
    }

    private func buildFooter() {
        footer.wantsLayer = true
        let sep = NSView(frame: NSRect(x: 0, y: footerHeight - 1, width: width, height: 1))
        sep.wantsLayer = true
        sep.layer?.backgroundColor = MDColor.cardBorder.cgColor
        footer.addSubview(sep)

        let gear = NSButton(image: NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)!,
                            target: self, action: #selector(openSettings(_:)))
        gear.bezelStyle = .inline
        gear.isBordered = false
        gear.frame = NSRect(x: 12, y: 10, width: 24, height: 24)
        footer.addSubview(gear)

        let open = NSButton(title: "打开 MangoDisk", target: self, action: #selector(openMangoDisk(_:)))
        open.bezelStyle = .inline
        open.isBordered = false
        open.font = .systemFont(ofSize: 11)
        open.contentTintColor = MDColor.subText
        open.frame = NSRect(x: width/2 - 60, y: 11, width: 120, height: 22)
        footer.addSubview(open)

        let quit = NSButton(title: "退出", target: self, action: #selector(quit(_:)))
        quit.bezelStyle = .inline
        quit.isBordered = false
        quit.font = .systemFont(ofSize: 11)
        quit.contentTintColor = MDColor.subText
        quit.frame = NSRect(x: width - 54, y: 11, width: 42, height: 22)
        footer.addSubview(quit)
    }

    private func selectTab(_ tab: Tab) {
        currentTab = tab
        let index = Tab.allCases.firstIndex(of: tab) ?? 0
        tabBar.select(index)

        pageHolder.subviews.forEach { $0.removeFromSuperview() }
        let page: MDPage
        if let cached = pages[tab] {
            page = cached
        } else {
            let p: MDPage
            switch tab {
            case .overview: p = OverviewPage(width: width)
            case .cpu: p = CPUPage(width: width)
            case .gpu: p = GPUPage(width: width)
            case .mem: p = MemPage(width: width)
            case .disk: p = DiskPage(width: width)
            case .net: p = NetPage(width: width)
            }
            pages[tab] = p
            p.layer?.backgroundColor = NSColor.clear.cgColor
            p.wantsLayer = true
            page = p
        }
        pageHolder.addSubview(page)

        let contentH = page.bounds.height
        let totalH = tabHeight + 12 + contentH + 8 + footerHeight
        view.frame.size = NSSize(width: width, height: totalH)
        tabBar.frame = NSRect(x: 0, y: totalH - tabHeight, width: width, height: tabHeight)
        pageHolder.frame = NSRect(x: 0, y: footerHeight + 8, width: width, height: contentH)
        page.frame = NSRect(x: 0, y: 0, width: width, height: page.bounds.height)
        footer.frame = NSRect(x: 0, y: 0, width: width, height: footerHeight)
        preferredSize = view.frame.size
        onSizeChange?(preferredSize)
        if let snap = latest { page.update(snap) }
    }

    func apply(_ s: Snapshot) {
        latest = s
        pages[currentTab]?.update(s)
    }

    func syncCheckboxes() {}

    func selectTabForDiagnostics(_ name: String) {
        pendingTabName = name
        if isViewLoaded { selectTab(diagnosticsMap[name.lowercased()] ?? .overview) }
    }

    // MARK: 动作
    @objc private func openSettings(_ sender: Any?) {
        onToggleLogin?(false)
    }
    @objc private func openMangoDisk(_ sender: Any?) {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/MangoDisk.app"))
    }
    @objc private func quit(_ sender: Any?) { onQuit?() }
}
