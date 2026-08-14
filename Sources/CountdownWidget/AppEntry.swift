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

                Button("切换禅模式悬浮窗") {
                    ZenHUDWindowController.shared.toggle(store: store)
                }
                .keyboardShortcut("m", modifiers: [.command])

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
    static let switchToCountdownRequested = Notification.Name("switchToCountdownRequested")
    static let switchToPomodoroRequested = Notification.Name("switchToPomodoroRequested")
    static let openPomodoroSettingsRequested = Notification.Name("openPomodoroSettingsRequested")
    static let showWidgetHelpRequested = Notification.Name("showWidgetHelpRequested")
    static let focusCountdownSearchRequested = Notification.Name("focusCountdownSearchRequested")
    static let showKeyboardShortcutsRequested = Notification.Name("showKeyboardShortcutsRequested")
    static let toggleZenHUDRequested = Notification.Name("toggleZenHUDRequested")
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
final class ZenHUDWindowController {
    static let shared = ZenHUDWindowController()
    private var panel: NSPanel?

    func toggle(store: CountdownStore) {
        if let panel = panel, panel.isVisible {
            panel.close()
            self.panel = nil
            return
        }
        show(store: store)
    }

    func show(store: CountdownStore) {
        if panel == nil {
            let p = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 280, height: 168),
                styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            p.isFloatingPanel = true
            p.level = .floating
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.titleVisibility = .hidden
            p.titlebarAppearsTransparent = true
            p.isMovableByWindowBackground = true
            p.backgroundColor = .clear
            p.isOpaque = false
            p.hasShadow = true

            let hosting = NSHostingView(
                rootView: ZenHUDView(store: store) { [weak self] in
                    self?.panel?.close()
                    self?.panel = nil
                }
                .environment(\.calendar, beijingCalendar)
                .environment(\.timeZone, beijingTimeZone)
                .environment(\.locale, beijingLocale)
            )
            p.contentView = hosting
            p.center()
            self.panel = p
        }
        panel?.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.close()
        panel = nil
    }
}

struct ZenHUDView: View {
    @ObservedObject var store: CountdownStore
    let onClose: () -> Void
    @State private var isHovering = false

    private var accent: Color { store.accentPreset.color }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.18), radius: 20, y: 8)

            VStack(spacing: 8) {
                // 顶部控制条
                HStack(spacing: 6) {
                    BrandMark(size: 18)
                    Text("禅模式")
                        .font(AppType.caption(11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if isHovering {
                        Button {
                            NSApp.activate(ignoringOtherApps: true)
                            if let window = NSApp.windows.first(where: { $0.title == "时隙" }) {
                                window.makeKeyAndOrderFront(nil)
                            }
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 20, height: 20)
                        }
                        .buttonStyle(.plain)
                        .help("展开主窗口")

                        Button {
                            onClose()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 20, height: 20)
                        }
                        .buttonStyle(.plain)
                        .help("关闭悬浮窗")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)

                // 中间展示区：倒计时 或 番茄钟
                if store.pomodoro.isRunning || store.pomodoro.isStopwatchActive {
                    pomodoroContent
                } else if let selected = store.selectedItem {
                    countdownContent(selected)
                } else {
                    pomodoroContent
                }
            }
            .padding(.bottom, 12)
        }
        .frame(width: 280, height: 168)
        .onHover { isHovering = $0 }
    }

    @ViewBuilder
    private var pomodoroContent: some View {
        let state = store.pomodoro
        let phaseColor = state.phase == .focus ? accent : Color(hex: state.phase.colorHex)
        let isStopwatch = state.isStopwatchActive
        let color = isStopwatch ? accent : phaseColor
        let isRunning = isStopwatch ? state.stopwatchRunning : state.isRunning

        TimelineView(.periodic(from: .now, by: 1)) { context in
            let prog = isStopwatch
                ? CGFloat(max(0, state.stopwatchElapsed(at: context.date)).truncatingRemainder(dividingBy: 60) / 60)
                : CGFloat(min(1, max(0, 1 - state.remaining(at: context.date) / max(1, state.duration(for: state.phase)))))

            HStack(spacing: 16) {
                ZStack {
                    TimeSlotRing(progress: prog, color: color, lineWidth: 6, showsGlow: isRunning)
                        .frame(width: 72, height: 72)

                    Image(systemName: isStopwatch ? "stopwatch.fill" : state.phase.icon)
                        .font(.system(size: 20))
                        .foregroundStyle(color)
                        .symbolEffect(.pulse, isActive: isRunning)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(isStopwatch ? "正计时" : state.phase.title)
                        .font(AppType.caption(12, weight: .semibold))
                        .foregroundStyle(color)

                    if isStopwatch {
                        Text(stopwatchFormat(state.stopwatchElapsed(at: context.date)))
                            .font(AppType.timer(22))
                            .monospacedDigit()
                            .foregroundStyle(color)
                    } else {
                        PomodoroTimerText(state: state, fontSize: 22, color: color)
                    }

                    HStack(spacing: 6) {
                        Button {
                            if isStopwatch {
                                store.startOrPauseStopwatch()
                            } else {
                                store.startOrPausePomodoro()
                            }
                        } label: {
                            Image(systemName: isRunning ? "pause.fill" : "play.fill")
                                .font(.system(size: 11, weight: .bold))
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(color)
                        .controlSize(.mini)

                        Button {
                            if isStopwatch {
                                store.resetStopwatch()
                            } else {
                                store.resetPomodoro()
                            }
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 11, weight: .semibold))
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                    .padding(.top, 2)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
        }
    }

    private func countdownContent(_ item: CountdownItem) -> some View {
        let color = Color(hex: item.colorHex)
        return TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = item.remaining(at: context.date)
            let isDone = remaining <= 0
            let total = max(1, item.totalDuration)
            let prog = CGFloat(isDone ? 1 : min(1, max(0.02, 1 - remaining / total)))

            HStack(spacing: 16) {
                ZStack {
                    TimeSlotRing(progress: prog, color: color, lineWidth: 6, showsGlow: !item.isPaused && !isDone)
                        .frame(width: 72, height: 72)

                    Image(systemName: isDone ? "checkmark" : (item.isPaused ? "pause.fill" : "timer"))
                        .font(.system(size: 20))
                        .foregroundStyle(color)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(AppType.ui(13, .semibold))
                        .lineLimit(1)

                    Text(remainingDisplayCompact(remaining))
                        .font(AppType.timer(20))
                        .monospacedDigit()
                        .foregroundStyle(color)

                    HStack(spacing: 6) {
                        Button {
                            store.togglePause(item)
                        } label: {
                            Image(systemName: item.isPaused ? "play.fill" : "pause.fill")
                                .font(.system(size: 11, weight: .bold))
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(color)
                        .controlSize(.mini)

                        Text(item.isPaused ? "已暂停" : (isDone ? "已到达" : "进行中"))
                            .font(AppType.caption(10.5))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 2)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
        }
    }

    private func remainingDisplayCompact(_ remaining: TimeInterval) -> String {
        guard remaining > 0 else { return "已到达" }
        let total = Int(ceil(remaining))
        let d = total / 86400
        let h = (total % 86400) / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if d > 0 { return "\(d)天 \(h)小时" }
        if h > 0 { return String(format: "%02d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }

    private func stopwatchFormat(_ elapsed: TimeInterval) -> String {
        let total = max(0, Int(elapsed))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
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
