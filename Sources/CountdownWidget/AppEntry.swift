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
                Button("桌面小组件使用说明") {
                    NotificationCenter.default.post(name: .showWidgetHelpRequested, object: nil)
                }
            }
        }
    }
}

extension Notification.Name {
    static let newCountdownRequested = Notification.Name("newCountdownRequested")
    static let switchToCountdownRequested = Notification.Name("switchToCountdownRequested")
    static let switchToPomodoroRequested = Notification.Name("switchToPomodoroRequested")
    static let openPomodoroSettingsRequested = Notification.Name("openPomodoroSettingsRequested")
    static let showWidgetHelpRequested = Notification.Name("showWidgetHelpRequested")
    static let focusCountdownSearchRequested = Notification.Name("focusCountdownSearchRequested")
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
