import AppKit
import SwiftUI
import Combine
import WidgetKit
import Charts
import UserNotifications
import UniformTypeIdentifiers

@main
struct CountdownWidgetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = CountdownStore()

    var body: some Scene {
        Window("时隙", id: "main") {
            ContentView(store: store)
                .frame(minWidth: 980, minHeight: 640)
                .environment(\.calendar, beijingCalendar)
                .environment(\.timeZone, beijingTimeZone)
                .environment(\.locale, beijingLocale)
        }
        .defaultSize(width: 1120, height: 780)
        .windowStyle(.hiddenTitleBar)

        Settings {
            AppSettingsPage(store: store)
                .frame(minWidth: 640, minHeight: 600)
                .background {
                    FrostedCanvas(theme: store.accentPreset)
                }
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("关于时隙") {
                    NSApp.orderFrontStandardAboutPanel(options: [
                        .applicationName: "时隙",
                        .credits: NSAttributedString(
                            string: "把倒计时与专注，固定在桌面",
                            attributes: [
                                .foregroundColor: NSColor.secondaryLabelColor,
                                .font: NSFont.systemFont(ofSize: 11)
                            ]
                        )
                    ])
                }
            }
            CommandGroup(replacing: .newItem) {
                Button("新建倒计时") {
                    NotificationCenter.default.post(name: .newCountdownRequested, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
            CommandMenu("视图") {
                Button("首页") {
                    NotificationCenter.default.post(name: .switchToHomeRequested, object: nil)
                }
                .keyboardShortcut("0", modifiers: [.command])

                Button("倒计时") {
                    NotificationCenter.default.post(name: .switchToCountdownRequested, object: nil)
                }
                .keyboardShortcut("1", modifiers: [.command])

                Button("番茄钟") {
                    NotificationCenter.default.post(name: .switchToPomodoroRequested, object: nil)
                }
                .keyboardShortcut("2", modifiers: [.command])

                Divider()

                Button("搜索倒计时") {
                    NotificationCenter.default.post(name: .focusCountdownSearchRequested, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command])
            }
            CommandGroup(after: .help) {
                Button("快捷键速查") {
                    NotificationCenter.default.post(name: .showKeyboardShortcutsRequested, object: nil)
                }
                .keyboardShortcut("/", modifiers: [.command])

                Button("桌面小组件使用说明") {
                    NotificationCenter.default.post(name: .showWidgetHelpRequested, object: nil)
                }
            }
        }
    }
}

extension Notification.Name {
    static let newCountdownRequested = Notification.Name("newCountdownRequested")
    static let switchToHomeRequested = Notification.Name("switchToHomeRequested")
    static let switchToCountdownRequested = Notification.Name("switchToCountdownRequested")
    static let switchToPomodoroRequested = Notification.Name("switchToPomodoroRequested")
    static let openPomodoroSettingsRequested = Notification.Name("openPomodoroSettingsRequested")
    static let showWidgetHelpRequested = Notification.Name("showWidgetHelpRequested")
    static let focusCountdownSearchRequested = Notification.Name("focusCountdownSearchRequested")
    static let showKeyboardShortcutsRequested = Notification.Name("showKeyboardShortcutsRequested")
}

@MainActor
enum BackupFileService {
    static func export(_ data: Data) throws -> URL? {
        let panel = NSSavePanel()
        let formatter = DateFormatter()
        formatter.locale = beijingLocale
        formatter.timeZone = beijingTimeZone
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        panel.nameFieldStringValue = "时隙备份-\(formatter.string(from: Date())).json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.message = "导出倒计时、专注记录、任务与显示设置"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        try data.write(to: url, options: .atomic)
        return url
    }

    static func chooseImportData() throws -> Data? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "选择之前由时隙导出的 JSON 备份"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        if let fileSize = values.fileSize,
           fileSize > BackupValidationPolicy.maximumFileSize {
            throw BackupValidationError.fileTooLarge
        }
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        UNUserNotificationCenter.current().delegate = self
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            for window in NSApp.windows where window.canBecomeMain {
                window.makeKeyAndOrderFront(nil)
            }
            malloc_zone_pressure_relief(nil, 0)
        }
        // 看板使用触控板/滚轮滚动；隐藏 AppKit 的粗滚动条，避免破坏内容边界。
        forceOverlayScrollers()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.forceOverlayScrollers()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            self?.forceOverlayScrollers()
        }
    }

    private func forceOverlayScrollers() {
        func walk(_ view: NSView) {
            if let scrollView = view as? NSScrollView {
                scrollView.scrollerStyle = .overlay
                scrollView.autohidesScrollers = true
                scrollView.hasVerticalScroller = false
                scrollView.hasHorizontalScroller = false
                scrollView.scrollerKnobStyle = colorSchemeScrollerKnob()
            }
            view.subviews.forEach(walk)
        }
        for window in NSApp.windows {
            if let contentView = window.contentView {
                walk(contentView)
            }
        }
    }

    private func colorSchemeScrollerKnob() -> NSScroller.KnobStyle {
        switch NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) {
        case .darkAqua: return .dark
        default: return .light
        }
    }

    func applicationDidResignActive(_ notification: Notification) {
        malloc_zone_pressure_relief(nil, 0)
    }

    func applicationDidHide(_ notification: Notification) {
        malloc_zone_pressure_relief(nil, 0)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        if !flag {
            for window in sender.windows where window.canBecomeMain {
                window.makeKeyAndOrderFront(nil)
                return true
            }
        }
        return true
    }

    /// 点击桌面小组件时打开应用：timeslot://countdown、timeslot://pomodoro
    func application(_ application: NSApplication, open urls: [URL]) {
        NSApp.activate(ignoringOtherApps: true)
        guard let url = urls.first, url.scheme?.lowercased() == "timeslot" else { return }
        switch url.host?.lowercased() {
        case "pomodoro":
            NotificationCenter.default.post(name: .switchToPomodoroRequested, object: nil)
        case "countdown":
            NotificationCenter.default.post(name: .switchToCountdownRequested, object: nil)
        default:
            break
        }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// 应用在前台时也展示横幅并响铃，倒计时结束时用户不会错过反馈。
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }
}
