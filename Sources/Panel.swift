import Cocoa
import ServiceManagement

final class PanelViewController: NSViewController {

    var onToggleBarItem: ((BarItem, Bool) -> Void)?
    var onQuit: (() -> Void)?
    var onToggleLogin: ((Bool) -> Void)?

    private let cpuRow = MetricRow(title: "CPU", hasBar: true, tint: .systemBlue)
    private let memRow = MetricRow(title: "内存", hasBar: true, tint: .systemGreen)
    private let netRow = MetricRow(title: "网络", hasSpark: true, tint: .systemPurple)
    private let diskRow = MetricRow(title: "磁盘", hasBar: true, hasSub: true, tint: .systemOrange)
    private let tempRow = MetricRow(title: "温度", hasSub: true, tint: .systemRed)

    private let uptimeLabel = NSTextField(labelWithString: "")
    private var checkboxes: [BarItem: NSButton] = [:]
    private let loginCheck = NSButton(checkboxWithTitle: "开机自启", target: nil, action: nil)

    private(set) var preferredSize = NSSize(width: 318, height: 360)

    override func loadView() {
        view = NSView(frame: NSRect(origin: .zero, size: preferredSize))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
    }

    // MARK: 构建界面

    private func buildUI() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 9
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 14)
        ])

        // 标题
        let titleLabel = NSTextField(labelWithString: "系统状态")
        titleLabel.font = .systemFont(ofSize: 12.5, weight: .semibold)
        uptimeLabel.font = .systemFont(ofSize: 10.5)
        uptimeLabel.textColor = .tertiaryLabelColor

        let header = NSStackView(views: [titleLabel, NSView(), uptimeLabel])
        header.orientation = .horizontal
        header.spacing = 6
        header.alignment = .centerY

        stack.addArrangedSubview(header)
        addRow(cpuRow, to: stack, widthOf: stack)
        addRow(memRow, to: stack, widthOf: stack)
        addRow(netRow, to: stack, widthOf: stack)
        addRow(diskRow, to: stack, widthOf: stack)
        addRow(tempRow, to: stack, widthOf: stack)

        stack.addArrangedSubview(separator(widthOf: stack))
        stack.addArrangedSubview(sectionLabel("菜单栏显示"))

        let boxes = NSStackView()
        boxes.orientation = .horizontal
        boxes.spacing = 14
        for item in BarItem.allCases {
            let box = NSButton(checkboxWithTitle: item.title, target: self,
                               action: #selector(toggleBarItem(_:)))
            box.font = .systemFont(ofSize: 11.5)
            box.controlSize = .small
            box.state = Settings.shared.barItems.contains(item) ? .on : .off
            checkboxes[item] = box
            boxes.addArrangedSubview(box)
        }
        stack.addArrangedSubview(boxes)

        stack.addArrangedSubview(separator(widthOf: stack))

        loginCheck.font = .systemFont(ofSize: 11.5)
        loginCheck.controlSize = .small
        loginCheck.target = self
        loginCheck.action = #selector(toggleLogin(_:))
        if #available(macOS 13.0, *) {
            loginCheck.state = SMAppService.mainApp.status == .enabled ? .on : .off
        }

        let quitButton = NSButton(title: "退出", target: self, action: #selector(quit(_:)))
        quitButton.bezelStyle = .rounded
        quitButton.controlSize = .small
        quitButton.font = .systemFont(ofSize: 11.5)

        let footer = NSStackView(views: [loginCheck, NSView(), quitButton])
        footer.orientation = .horizontal
        footer.spacing = 8
        footer.alignment = .centerY
        stack.addArrangedSubview(footer)
        footer.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        header.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        boxes.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        view.layoutSubtreeIfNeeded()
        let height = stack.fittingSize.height + 30
        preferredSize = NSSize(width: 318, height: ceil(height))
        view.frame.size = preferredSize
        stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -14).isActive = true
    }

    private func addRow(_ row: MetricRow, to stack: NSStackView, widthOf: NSStackView) {
        stack.addArrangedSubview(row)
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: row.height).isActive = true
        row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func sectionLabel(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: 10.5, weight: .medium)
        l.textColor = .tertiaryLabelColor
        return l
    }

    private func separator(widthOf stack: NSStackView) -> NSView {
        let box = NSBox()
        box.boxType = .separator
        box.heightAnchor.constraint(equalToConstant: 1).isActive = true
        box.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return box
    }

    // MARK: 刷新

    func apply(_ s: Snapshot) {
        cpuRow.set(value: String(format: "%.1f%%", s.cpu * 100))
        cpuRow.bar.value = s.cpu

        memRow.set(value: "\(Fmt.gb(s.memUsed)) / \(Fmt.gb(s.memTotal)) GB")
        memRow.bar.value = s.memTotal > 0 ? Double(s.memUsed) / Double(s.memTotal) : 0

        netRow.set(value: "↓ \(Fmt.rate(s.netDown))   ↑ \(Fmt.rate(s.netUp))")
        netRow.spark.push(down: s.netDown, up: s.netUp)

        let usedDisk = max(0, s.diskTotal - s.diskFree)
        diskRow.set(value: "已用 \(Fmt.bytes(Double(usedDisk))) / \(Fmt.bytes(Double(s.diskTotal)))",
                    sub: "读 \(Fmt.rate(s.diskRead)) · 写 \(Fmt.rate(s.diskWrite))")
        diskRow.bar.value = s.diskTotal > 0 ? Double(usedDisk) / Double(s.diskTotal) : 0

        if let t = s.cpuTemp {
            let fan = s.fanRPM.map { "风扇 \($0) rpm" } ?? "无风扇机型"
            tempRow.set(value: String(format: "%.1f °C", t), sub: "CPU 核心 · \(fan)")
        } else {
            tempRow.set(value: "—", sub: "温度传感器不可用")
        }

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
