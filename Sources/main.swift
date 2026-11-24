import Cocoa
import ServiceManagement

// MARK: - 菜单栏显示项

enum BarItem: String, CaseIterable {
    case cpu, mem, net, disk

    var title: String {
        switch self {
        case .cpu: return "CPU"
        case .mem: return "内存"
        case .net: return "网络"
        case .disk: return "磁盘"
        }
    }
}

final class Settings {
    static let shared = Settings()
    private let store = UserDefaults.standard

    var barItems: Set<BarItem> {
        get {
            guard let raw = store.array(forKey: "barItems") as? [String] else {
                return [.cpu, .mem, .net]
            }
            return Set(raw.compactMap(BarItem.init(rawValue:)))
        }
        set {
            store.set(newValue.map { $0.rawValue }.sorted(), forKey: "barItems")
        }
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
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

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = makeStatusImage(text: "启动中")
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        _ = panel.view    // 提前构建界面，拿到尺寸
        popover.contentSize = panel.preferredSize

        panel.onToggleBarItem = { [weak self] item, on in
            var items = Settings.shared.barItems
            if on { items.insert(item) } else { items.remove(item) }
            Settings.shared.barItems = items
            self?.lastTitle = ""
            if let snap = self?.latest { self?.updateBar(snap) }
        }
        panel.onQuit = { NSApp.terminate(nil) }
        panel.onToggleLogin = { [weak self] on in self?.setLoginItem(on) }

        startTimer()
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

    private func updateBar(_ snap: Snapshot) {
        var parts: [String] = []
        let items = Settings.shared.barItems

        if items.contains(.cpu) {
            parts.append("\(Fmt.percent(snap.cpu))%")
        }
        if items.contains(.mem) {
            parts.append(Fmt.gb(snap.memUsed) + "G")
        }
        if items.contains(.net) {
            parts.append("↓\(Fmt.compactRate(snap.netDown))↑\(Fmt.compactRate(snap.netUp))")
        }
        if items.contains(.disk) {
            let ratio = snap.diskTotal > 0
                ? Double(snap.diskTotal - snap.diskFree) / Double(snap.diskTotal) : 0
            parts.append("盘\(Fmt.percent(ratio))%")
        }

        let text = parts.isEmpty ? "—" : parts.joined(separator: "  ")
        guard text != lastTitle else { return }
        lastTitle = text
        statusItem.button?.image = makeStatusImage(text: text)
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
    风扇       : \(fan)
    已运行     : \(Fmt.uptime(snap.uptime))
    """)
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
