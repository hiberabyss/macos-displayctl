import AppKit
import CoreGraphics
import Darwin

private typealias ConfigureDisplayEnabled = @convention(c) (
    CGDisplayConfigRef?, CGDirectDisplayID, Bool
) -> CGError

private struct DisplayInfo: Hashable {
    let id: CGDirectDisplayID
    let name: String
    let isBuiltIn: Bool
    let isEnabled: Bool
    let width: Int
    let height: Int
}

private enum DisplayControlError: LocalizedError {
    case privateAPIUnavailable
    case enumerationFailed(CGError)
    case configurationFailed(CGError)
    case noExternalDisplay

    var errorDescription: String? {
        switch self {
        case .privateAPIUnavailable:
            return "当前 macOS 版本不提供 CGSConfigureDisplayEnabled。"
        case .enumerationFailed(let error):
            return "无法读取显示器列表（错误码：\(error.rawValue)）。"
        case .configurationFailed(let error):
            return "无法应用显示器配置（错误码：\(error.rawValue)）。"
        case .noExternalDisplay:
            return "关闭内置显示器前，必须至少保留一台活动的外接显示器。"
        }
    }
}

@MainActor
private final class DisplayController {
    static let shared = DisplayController()

    private let disabledDisplaysKey = "disabledDisplays"
    private let configureDisplayEnabled: ConfigureDisplayEnabled?

    private init() {
        let path = "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics"
        guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL),
              let symbol = dlsym(handle, "CGSConfigureDisplayEnabled") else {
            configureDisplayEnabled = nil
            return
        }
        configureDisplayEnabled = unsafeBitCast(symbol, to: ConfigureDisplayEnabled.self)
    }

    func displays() throws -> [DisplayInfo] {
        let online = try onlineDisplays()
        let onlineIDs = Set(online.map(\.id))
        let disabled = savedDisplays().filter { !onlineIDs.contains($0.id) }
        return (online + disabled).sorted {
            if $0.isBuiltIn != $1.isBuiltIn { return $0.isBuiltIn }
            return $0.id < $1.id
        }
    }

    func setEnabled(_ enabled: Bool, display: DisplayInfo) throws {
        guard let configureDisplayEnabled else {
            throw DisplayControlError.privateAPIUnavailable
        }

        if !enabled && display.isBuiltIn {
            let hasActiveExternal = try onlineDisplays().contains {
                !$0.isBuiltIn && $0.isEnabled && $0.id != display.id
            }
            guard hasActiveExternal else {
                throw DisplayControlError.noExternalDisplay
            }
        }

        var configuration: CGDisplayConfigRef?
        var error = CGBeginDisplayConfiguration(&configuration)
        guard error == .success, let configuration else {
            throw DisplayControlError.configurationFailed(error)
        }

        error = configureDisplayEnabled(configuration, display.id, enabled)
        guard error == .success else {
            CGCancelDisplayConfiguration(configuration)
            throw DisplayControlError.configurationFailed(error)
        }

        error = CGCompleteDisplayConfiguration(configuration, .forSession)
        guard error == .success else {
            throw DisplayControlError.configurationFailed(error)
        }

        if enabled {
            removeSavedDisplay(id: display.id)
        } else {
            saveDisplay(display)
        }
    }

    private func onlineDisplays() throws -> [DisplayInfo] {
        var count: UInt32 = 0
        var error = CGGetOnlineDisplayList(0, nil, &count)
        guard error == .success else {
            throw DisplayControlError.enumerationFailed(error)
        }

        var ids = Array(repeating: CGDirectDisplayID(), count: Int(count))
        error = CGGetOnlineDisplayList(count, &ids, &count)
        guard error == .success else {
            throw DisplayControlError.enumerationFailed(error)
        }

        return ids.prefix(Int(count)).map { id in
            DisplayInfo(
                id: id,
                name: displayName(id: id),
                isBuiltIn: CGDisplayIsBuiltin(id) != 0,
                isEnabled: CGDisplayIsActive(id) != 0,
                width: CGDisplayPixelsWide(id),
                height: CGDisplayPixelsHigh(id)
            )
        }
    }

    private func displayName(id: CGDirectDisplayID) -> String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[key] as? NSNumber)?.uint32Value == id
        }) {
            return screen.localizedName
        }
        return CGDisplayIsBuiltin(id) != 0 ? "内置显示器" : "外接显示器 \(id)"
    }

    private func savedDisplays() -> [DisplayInfo] {
        guard let records = UserDefaults.standard.array(forKey: disabledDisplaysKey)
                as? [[String: Any]] else { return [] }
        return records.compactMap { record in
            guard let id = record["id"] as? NSNumber,
                  let name = record["name"] as? String,
                  let builtIn = record["builtIn"] as? Bool else { return nil }
            return DisplayInfo(
                id: id.uint32Value,
                name: name,
                isBuiltIn: builtIn,
                isEnabled: false,
                width: record["width"] as? Int ?? 0,
                height: record["height"] as? Int ?? 0
            )
        }
    }

    private func saveDisplay(_ display: DisplayInfo) {
        var displays = savedDisplays().filter { $0.id != display.id }
        displays.append(DisplayInfo(
            id: display.id,
            name: display.name,
            isBuiltIn: display.isBuiltIn,
            isEnabled: false,
            width: display.width,
            height: display.height
        ))
        let records: [[String: Any]] = displays.map {
            [
                "id": NSNumber(value: $0.id),
                "name": $0.name,
                "builtIn": $0.isBuiltIn,
                "width": $0.width,
                "height": $0.height
            ]
        }
        UserDefaults.standard.set(records, forKey: disabledDisplaysKey)
    }

    private func removeSavedDisplay(id: CGDirectDisplayID) {
        let displays = savedDisplays().filter { $0.id != id }
        let records: [[String: Any]] = displays.map {
            [
                "id": NSNumber(value: $0.id),
                "name": $0.name,
                "builtIn": $0.isBuiltIn,
                "width": $0.width,
                "height": $0.height
            ]
        }
        UserDefaults.standard.set(records, forKey: disabledDisplaysKey)
    }
}

@MainActor
private final class DisplayRowView: NSView {
    private let display: DisplayInfo
    private let toggle = NSSwitch()
    private let onToggle: (DisplayInfo, Bool, NSSwitch) -> Void

    init(display: DisplayInfo,
         onToggle: @escaping (DisplayInfo, Bool, NSSwitch) -> Void) {
        self.display = display
        self.onToggle = onToggle
        super.init(frame: NSRect(x: 0, y: 0, width: 330, height: 62))
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        let icon = NSImageView()
        icon.image = NSImage(
            systemSymbolName: display.isBuiltIn ? "laptopcomputer" : "display",
            accessibilityDescription: display.isBuiltIn ? "内置显示器" : "外接显示器"
        )
        icon.contentTintColor = display.isEnabled ? .controlAccentColor : .secondaryLabelColor
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: display.name)
        title.font = .systemFont(ofSize: 13, weight: .medium)
        title.lineBreakMode = .byTruncatingTail

        let type = display.isBuiltIn ? "内置" : "外接"
        let resolution = display.width > 0 ? " · \(display.width) × \(display.height)" : ""
        let subtitle = NSTextField(labelWithString: "\(type) · ID \(display.id)\(resolution)")
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingTail

        let labels = NSStackView(views: [title, subtitle])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 3
        labels.translatesAutoresizingMaskIntoConstraints = false

        toggle.state = display.isEnabled ? .on : .off
        toggle.target = self
        toggle.action = #selector(toggleChanged(_:))
        toggle.setAccessibilityLabel("\(display.name)开关")
        toggle.translatesAutoresizingMaskIntoConstraints = false

        addSubview(icon)
        addSubview(labels)
        addSubview(toggle)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 25),
            icon.heightAnchor.constraint(equalToConstant: 25),
            labels.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 11),
            labels.centerYAnchor.constraint(equalTo: centerYAnchor),
            labels.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -12),
            toggle.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            toggle.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @objc private func toggleChanged(_ sender: NSSwitch) {
        sender.isEnabled = false
        onToggle(display, sender.state == .on, sender)
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private var refreshWorkItem: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "display.2",
                accessibilityDescription: "显示器控制"
            )
            button.toolTip = "显示器控制"
        }
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        rebuildMenu()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(displayConfigurationChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }

    @objc private func displayConfigurationChanged() {
        refreshWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.rebuildMenu() }
        refreshWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: item)
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        let header = NSMenuItem(title: "显示器", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        do {
            let displays = try DisplayController.shared.displays()
            if displays.isEmpty {
                let empty = NSMenuItem(title: "未检测到显示器", action: nil, keyEquivalent: "")
                empty.isEnabled = false
                menu.addItem(empty)
            } else {
                for display in displays {
                    let item = NSMenuItem()
                    item.view = DisplayRowView(display: display) { [weak self] display, enabled, toggle in
                        self?.setEnabled(enabled, display: display, toggle: toggle)
                    }
                    menu.addItem(item)
                }
            }
        } catch {
            let item = NSMenuItem(title: "读取显示器失败", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let refresh = NSMenuItem(
            title: "刷新显示器列表",
            action: #selector(refreshDisplays),
            keyEquivalent: "r"
        )
        refresh.target = self
        menu.addItem(refresh)

        let quit = NSMenuItem(
            title: "退出 macos-displayctl",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quit)
    }

    private func setEnabled(_ enabled: Bool, display: DisplayInfo, toggle: NSSwitch) {
        do {
            try DisplayController.shared.setEnabled(enabled, display: display)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.rebuildMenu()
            }
        } catch {
            toggle.state = display.isEnabled ? .on : .off
            toggle.isEnabled = true
            showError(error)
        }
    }

    @objc private func refreshDisplays() {
        rebuildMenu()
    }

    private func showError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "无法更改显示器状态"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}

@main
private struct DisplayCtlApplication {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
        withExtendedLifetime(delegate) {}
    }
}
