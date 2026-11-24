import Cocoa
import ServiceManagement

// MARK: - 菜单栏显示项

enum BarItem: String, CaseIterable {
    case cpu, cpuTemp, gpu, gpuTemp, mem, diskTemp, net, power

    /// 面板开关上的中文名
    var title: String {
        switch self {
        case .cpu: return "CPU"
        case .cpuTemp: return "CPU温度"
        case .gpu: return "GPU"
        case .gpuTemp: return "GPU温度"
        case .mem: return "内存"
        case .diskTemp: return "磁盘温度"
        case .net: return "网络"
        case .power: return "功耗"
        }
    }

    /// 菜单栏上的英文小标签（MangoDisk 风格）
    var label: String {
        switch self {
        case .cpu: return "CPU"
        case .cpuTemp: return "CPU"
        case .gpu: return "GPU"
        case .gpuTemp: return "GPU"
        case .mem: return "MEM"
        case .diskTemp: return "DISK"
        case .net: return "NET"
        case .power: return "SYS"
        }
    }
}

final class Settings {
    static let shared = Settings()
    private let store = UserDefaults.standard

    var barItems: Set<BarItem> {
        get {
            guard let raw = store.array(forKey: "barItems") as? [String] else {
                return Set(BarItem.allCases)   // 默认全开
            }
            let parsed = Set(raw.compactMap(BarItem.init(rawValue:)))
            return parsed.isEmpty ? Set(BarItem.allCases) : parsed
        }
        set {
            store.set(newValue.map { $0.rawValue }.sorted(), forKey: "barItems")
        }
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItems: [BarItem: NSStatusItem] = [:]
    private var lastValues: [BarItem: String] = [:]
    private let panel = PanelViewController()
    private lazy var popover: NSPopover = {
        let p = NSPopover()
        p.behavior = .transient
        p.animates = false
        p.contentViewController = panel
        return p
    }()

    private let sampler = Sampler()
    private let queue = DispatchQueue(label: "glance.sampler", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var latest: Snapshot?
    private var lastTitle = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // MangoDisk 风格：每个指标一个独立状态项
        for item in BarItem.allCases where Settings.shared.barItems.contains(item) {
            let si = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            if let button = si.button {
                button.attributedTitle = makeMetricTitle(label: item.label, value: "…")
                button.target = self
                button.action = #selector(statusItemClicked(_:))
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            }
            statusItems[item] = si
        }

        // 不在启动时强制构建 panel.view：popover 首次显示时会自行懒加载，
        // 避免在 applicationDidFinishLaunching 阶段做多余的布局计算。
        popover.contentSize = panel.preferredSize

        panel.onToggleBarItem = { [weak self] item, on in
            guard let self else { return }
            var items = Settings.shared.barItems
            if on { items.insert(item) } else { items.remove(item) }
            Settings.shared.barItems = items
            self.applyStatusItemPresence()
            if let snap = self.latest { self.updateBar(snap) }
        }
        panel.onQuit = { NSApp.terminate(nil) }
        panel.onToggleLogin = { [weak self] on in self?.setLoginItem(on) }
        panel.onSizeChange = { [weak self] size in
            self?.popover.contentSize = size
        }

        startTimer()

        // 诊断：--popover 启动后自动弹出面板，便于截图验证布局
        if CommandLine.arguments.contains("--popover"), let item = statusItems[.cpu], let button = item.button {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                guard let self else { return }
                self.panel.syncCheckboxes()
                if let snap = self.latest { self.panel.apply(snap) }
                if let tabArg = CommandLine.arguments.first(where: { $0.hasPrefix("--tab=") }) {
                    let name = String(tabArg.dropFirst("--tab=".count))
                    self.panel.selectTabForDiagnostics(name)
                }
                self.popover.contentSize = self.panel.preferredSize
                self.popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                self.popover.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    // MARK: 采样循环

    private func startTimer() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: 1.0, leeway: .milliseconds(120))
        t.setEventHandler { [weak self] in
            guard let self else { return }
            let snap = self.sampler.sample()
            DispatchQueue.main.async {
                self.latest = snap
                self.updateBar(snap)
                if self.popover.isShown { self.panel.apply(snap) }
            }
        }
        t.resume()
        timer = t
    }

    /// 按当前开关增删状态项（开关变化时调用）
    private func applyStatusItemPresence() {
        let enabled = Settings.shared.barItems
        // 移除已关闭的
        for (item, si) in statusItems where !enabled.contains(item) {
            NSStatusBar.system.removeStatusItem(si)
            statusItems[item] = nil
            lastValues[item] = nil
        }
        // 添加新开启的
        for item in BarItem.allCases where enabled.contains(item) && statusItems[item] == nil {
            let si = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            if let button = si.button {
                button.attributedTitle = makeMetricTitle(label: item.label, value: "…")
                button.target = self
                button.action = #selector(statusItemClicked(_:))
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            }
            statusItems[item] = si
        }
    }

    /// 每项独立渲染（MangoDisk 风格：上小标签 + 下数值）
    private func updateBar(_ snap: Snapshot) {
        let memPct = snap.memTotal > 0 ? Double(snap.memUsed) / Double(snap.memTotal) : 0
        let values: [BarItem: String] = [
            .cpu: "\(Fmt.percent(snap.cpu))%",
            .cpuTemp: snap.cpuTemp.map { "\(Int($0.rounded()))°" } ?? "—",
            .gpu: snap.gpuUtil.map { "\(Fmt.percent($0))%" } ?? "—",
            .gpuTemp: snap.gpuTemp.map { "\(Int($0.rounded()))°" } ?? "—",
            .mem: "\(Fmt.percent(memPct))%",
            .diskTemp: snap.diskTemp.map { "\(Int($0.rounded()))°" } ?? "—",
            .net: "↑\(Fmt.compactRate(snap.netUp))↓\(Fmt.compactRate(snap.netDown))",
            .power: snap.power.map { "\(String(format: "%.0f", $0))W" } ?? "—"
        ]
        for (item, value) in values {
            guard let si = statusItems[item] else { continue }
            guard lastValues[item] != value else { continue }  // 没变化就不重绘
            lastValues[item] = value
            if item == .net {
                // MangoDisk 网络项：上行红↑上传、下行蓝↓下载，无标签
                let parts = value.dropFirst().split(whereSeparator: { $0 == "↑" || $0 == "↓" })
                let up = parts.count > 0 ? String(parts[0]) : "0 B/s"
                let down = parts.count > 1 ? String(parts[1]) : "0 B/s"
                si.button?.attributedTitle = makeNetworkTitle(up: up, down: down)
            } else {
                si.button?.attributedTitle = makeMetricTitle(label: item.label, value: value)
            }
        }
    }

    // MARK: 交互

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let isRight = NSApp.currentEvent?.type == .rightMouseUp
            || NSApp.currentEvent?.modifierFlags.contains(.control) == true

        if isRight {
            showContextMenu(sender)
        } else {
            togglePopover(sender)
        }
    }

    private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        panel.syncCheckboxes()
        if let snap = latest { panel.apply(snap) }
        // 尺寸在 selectTab 后会变化，显示前同步
        popover.contentSize = panel.preferredSize
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showContextMenu(_ sender: NSStatusBarButton) {
        let menu = NSMenu()
        let refresh = NSMenuItem(title: "刷新一次", action: #selector(refreshNow), keyEquivalent: "")
        refresh.target = self
        menu.addItem(refresh)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 Glance", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        sender.menu = menu
        menu.popUp(positioning: nil,
                   at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    @objc private func refreshNow() {
        queue.async { [weak self] in
            guard let self else { return }
            let snap = self.sampler.sample()
            DispatchQueue.main.async {
                self.latest = snap
                self.updateBar(snap)
                if self.popover.isShown { self.panel.apply(snap) }
            }
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: 开机自启

    private func setLoginItem(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "设置开机自启失败"
            alert.informativeText = "\(error.localizedDescription)\n\n提示：把 Glance.app 放进「应用程序」文件夹后再试。"
            alert.alertStyle = .warning
            alert.runModal()
        }
    }
}

// MARK: 入口

// 命令行诊断：把指定标签页渲染成 PNG 保存，绕开状态栏/窗口遮挡问题
if let renderArg = CommandLine.arguments.first(where: { $0.hasPrefix("--render=") }) {
    let tabName = String(renderArg.dropFirst("--render=".count))
    let s = Sampler()
    usleep(1_200_000)
    let snap = s.sample()
    let panel = PanelViewController()
    _ = panel.view                       // 触发 loadView + viewDidLoad
    panel.selectTabForDiagnostics(tabName)
    panel.apply(snap)
    panel.view.frame = NSRect(origin: .zero, size: panel.preferredSize)
    panel.view.layoutSubtreeIfNeeded()
    if let rep = panel.view.bitmapImageRepForCachingDisplay(in: panel.view.bounds) {
        panel.view.cacheDisplay(in: panel.view.bounds, to: rep)
        if let tiff = rep.tiffRepresentation, let img = NSBitmapImageRep(data: tiff),
           let png = img.representation(using: .png, properties: [:]) {
            let path = "/tmp/glance_render_\(tabName).png"
            try? png.write(to: URL(fileURLWithPath: path))
            print("rendered \(path) size=\(panel.preferredSize)")
        }
    }
    exit(0)
}

// 命令行诊断模式：Glance --dump 输出一次完整采样后退出
if CommandLine.arguments.contains("--dump") {
    let s = Sampler()
    usleep(1_200_000) // 等待第二个采样窗口，让速率类指标有基线
    let snap = s.sample()
    let fan = snap.fanRPM.map { "\($0) rpm" } ?? "无"
    let temp = snap.cpuTemp.map { String(format: "%.1f", $0) } ?? "不可用"
    print("""
    CPU        : \(String(format: "%.1f%%", snap.cpu * 100))  (\(snap.cpuCores) 核)
    内存       : \(Fmt.gb(snap.memUsed)) / \(Fmt.gb(snap.memTotal)) GB
    网络       : ↓\(Fmt.rate(snap.netDown))  ↑\(Fmt.rate(snap.netUp))
    磁盘       : 已用 \(Fmt.bytes(Double(snap.diskTotal - snap.diskFree))) / \(Fmt.bytes(Double(snap.diskTotal)))
    磁盘 IO    : 读 \(Fmt.rate(snap.diskRead))  写 \(Fmt.rate(snap.diskWrite))
    CPU 温度   : \(temp) °C
    磁盘温度   : \(snap.diskTemp.map { String(format: "%.1f", $0) } ?? "不可用") °C
    GPU 温度   : \(snap.gpuTemp.map { String(format: "%.1f", $0) } ?? "不可用") °C
    GPU 占用   : \(snap.gpuUtil.map { String(format: "%.0f%%", $0 * 100) } ?? "不可用")
    系统功耗   : \(snap.power.map { String(format: "%.1f", $0) } ?? "不可用") W
    风扇       : \(fan)
    已运行     : \(Fmt.uptime(snap.uptime))
    进程 sample: \(snap.processes.count) 个
    \(snap.processes.sorted { $0.cpu > $1.cpu }.prefix(5).map { "  \($0.name)  CPU \(String(format: "%.1f%%", $0.cpu * 100))  MEM \(Fmt.bytes(Double($0.memory)))" }.joined(separator: "\n"))
    """)
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
