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

                Divider()

                Button("搜索倒计时") {
                    NotificationCenter.default.post(name: .focusCountdownSearchRequested, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command])
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

private struct SettingsView: View {
    @ObservedObject var store: CountdownStore
    @State private var pendingImport: BackupPayload?
    @State private var showingImportConfirm = false
    @State private var operationError: String?

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
                do {
                    try store.applyBackup(payload)
                } catch {
                    operationError = error.localizedDescription
                }
                pendingImport = nil
            }
            Button("取消", role: .cancel) {
                pendingImport = nil
            }
        } message: { payload in
            Text("将导入 \(payload.items.count) 个倒计时、\(payload.history.count) 条阶段记录。当前数据会先自动备份；如果备份失败，不会更改任何数据。")
                .lineSpacing(2.5)
        }
        .alert(
            "无法完成操作",
            isPresented: Binding(
                get: { operationError != nil },
                set: { if !$0 { operationError = nil } }
            )
        ) {
            Button("好", role: .cancel) { operationError = nil }
        } message: {
            Text(operationError ?? "未知错误")
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
        guard let data = store.exportBackup() else {
            operationError = "当前数据无法编码为备份。"
            return
        }
        do {
            _ = try BackupFileService.export(data)
        } catch {
            operationError = error.localizedDescription
        }
    }

    private func chooseImportBackup() {
        do {
            guard let data = try BackupFileService.chooseImportData() else { return }
            pendingImport = try CountdownStore.decodeBackup(data)
            showingImportConfirm = true
        } catch {
            operationError = error.localizedDescription
        }
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
