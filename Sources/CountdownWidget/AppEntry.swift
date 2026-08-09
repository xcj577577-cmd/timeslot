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
        WindowGroup {
            ContentView(store: store)
                .frame(minWidth: 980, minHeight: 640)
                .environment(\.calendar, beijingCalendar)
                .environment(\.timeZone, beijingTimeZone)
                .environment(\.locale, beijingLocale)
        }
        .defaultSize(width: 1120, height: 780)
        .windowStyle(.hiddenTitleBar)
        Settings {
            SettingsView(store: store)
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
            }
            CommandMenu("帮助") {
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
}

private struct SettingsView: View {
    @ObservedObject var store: CountdownStore
    @State private var pendingImport: BackupPayload?
    @State private var showingImportConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("通用")
                .font(.system(size: Typo.body, weight: .semibold))
                .tracking(Tracking.heading)

            Toggle("通知提醒", isOn: notificationsBinding)
            Text("番茄钟阶段结束、倒计时完成时，通过系统通知提醒（需在系统设置中允许通知）。")
                .font(.system(size: Typo.caption))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("提示音", isOn: soundsBinding)
            Text("计时结束时播放提示音；未授予通知权限时，提示音是唯一的结束提醒。")
                .font(.system(size: Typo.caption))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Text("数据")
                .font(.system(size: Typo.body, weight: .semibold))
                .tracking(Tracking.heading)

            HStack(spacing: Space.m) {
                Button("导出备份") { exportBackup() }
                Button("导入备份") { chooseImportBackup() }
                Button("番茄钟设置…") {
                    NotificationCenter.default.post(name: .openPomodoroSettingsRequested, object: nil)
                    // 关闭设置窗口，让主窗口里的番茄钟设置弹窗可见。
                    // 注意：closeWindow: 不是有效 selector，sendAction 会静默失败，必须用实例方法。
                    NSApp.keyWindow?.close()
                }
            }
            Text("备份包含全部倒计时、番茄钟记录、任务与显示设置，仅保存在本机，可随时恢复。")
                .font(.system(size: Typo.caption))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.xl)
        .frame(width: 460)
        .alert(
            "导入备份？",
            isPresented: $showingImportConfirm,
            presenting: pendingImport
        ) { payload in
            Button("导入并覆盖当前数据", role: .destructive) {
                store.applyBackup(payload)
                pendingImport = nil
            }
            Button("取消", role: .cancel) {
                pendingImport = nil
            }
        } message: { _ in
            Text("导入会覆盖当前全部数据，且无法撤销。建议先「导出备份」再导入。")
                .lineSpacing(2.5)
        }
    }

    private var notificationsBinding: Binding<Bool> {
        Binding(
            get: { store.notificationsEnabled },
            set: { store.setNotificationsEnabled($0) }
        )
    }

    private var soundsBinding: Binding<Bool> {
        Binding(
            get: { store.soundsEnabled },
            set: { store.setSoundsEnabled($0) }
        )
    }

    private func exportBackup() {
        guard let data = store.exportBackup() else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "时隙备份-\(Date().formatted(.dateTime.year().month().day().hour().minute().second()))"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func chooseImportBackup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.message = "选择之前导出的时隙备份文件"
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url),
              let payload = try? CountdownStore.decodeBackup(data) else { return }
        pendingImport = payload
        showingImportConfirm = true
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
