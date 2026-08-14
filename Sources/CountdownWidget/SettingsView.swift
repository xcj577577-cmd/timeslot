import AppKit
import SwiftUI

/// 应用内设置页：提醒、桌面小组件偏好、番茄钟节奏、数据与关于。
/// 系统「设置…」（⌘,）与应用内设置共用这一页，避免两套设置逻辑漂移。
struct AppSettingsPage: View {
    @ObservedObject var store: CountdownStore
    @State private var showingPomodoroSettings = false
    @State private var showingClearHistoryConfirmation = false
    @State private var pendingImport: BackupPayload?
    @State private var showingImportConfirmation = false
    @State private var operationError: String?
    @State private var selectedSoundPreset: SoundEffectPreset = .glass

    private var soundPresetBinding: Binding<SoundEffectPreset> {
        Binding(
            get: {
                if let raw = UserDefaults.standard.string(forKey: "timeslot_sound_preset"),
                   let preset = SoundEffectPreset(rawValue: raw) {
                    return preset
                }
                return .glass
            },
            set: { newValue in
                selectedSoundPreset = newValue
                UserDefaults.standard.set(newValue.rawValue, forKey: "timeslot_sound_preset")
            }
        )
    }

    private var accent: Color { store.accentPreset.color }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("设置")
                        .font(AppType.pageTitle())
                        .tracking(Tracking.pageTitle)
                    Text("提醒、小组件与专注节奏")
                        .font(AppType.ui(Typo.footnote))
                        .foregroundStyle(.secondary)
                }

                settingsCard(title: "声音与专注音效", icon: "speaker.wave.2.fill") {
                    Toggle(isOn: soundsBinding) {
                        settingLabel(title: "阶段结束提示音", subtitle: "倒计时到达或番茄钟阶段结束时播放声音")
                    }
                    .toggleStyle(.switch)
                    .tint(accent)
                    .accessibilityIdentifier("timeslot.settings.sounds.toggle")

                    if store.soundsEnabled {
                        HStack(spacing: Space.m) {
                            Text("音效选择")
                                .font(AppType.ui(Typo.footnote, .medium))
                            Spacer()
                            Picker("提示音", selection: soundPresetBinding) {
                                ForEach(SoundEffectPreset.allCases) { preset in
                                    Text(preset.rawValue).tag(preset)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(width: 120)

                            Button {
                                selectedSoundPreset.play()
                            } label: {
                                Image(systemName: "play.circle.fill")
                                    .font(AppType.ui(Typo.body, .medium))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(accent)
                            .help("试听当前提示音")
                        }
                        .padding(.vertical, 4)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: Space.s) {
                        HStack(spacing: Space.s) {
                            Text("专注背景白噪音")
                                .font(AppType.ui(Typo.footnote, .medium))
                            Spacer()
                            Picker("白噪音类型", selection: Binding(
                                get: { FocusAmbiencePlayer.shared.currentSound },
                                set: { FocusAmbiencePlayer.shared.selectSound($0) }
                            )) {
                                ForEach(FocusAmbienceSound.allCases) { sound in
                                    Text(sound.rawValue).tag(sound)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(width: 120)
                        }

                        if FocusAmbiencePlayer.shared.currentSound != .off {
                            HStack(spacing: Space.m) {
                                Image(systemName: "speaker.wave.2.fill")
                                    .font(AppType.caption())
                                    .foregroundStyle(.secondary)
                                Slider(value: Binding(
                                    get: { FocusAmbiencePlayer.shared.volume },
                                    set: { FocusAmbiencePlayer.shared.volume = $0 }
                                ), in: 0...1)
                                Text("\(Int(FocusAmbiencePlayer.shared.volume * 100))%")
                                    .font(AppType.caption())
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                    .frame(width: 32, alignment: .trailing)
                            }
                            .padding(.top, 2)
                        }
                    }

                    Divider()

                    Toggle(isOn: notificationsBinding) {
                        settingLabel(title: "系统横幅通知", subtitle: "允许在屏幕右上角显示 macOS 系统通知")
                    }
                    .toggleStyle(.switch)
                    .tint(accent)
                    .accessibilityIdentifier("timeslot.settings.notifications.toggle")

                    notificationPermissionStatus
                }

                settingsCard(title: "外观", icon: "circle.lefthalf.filled") {
                    TimeSlotSegmentedControl(
                        options: AppAppearance.allCases.map {
                            SegmentOption(id: $0.rawValue, title: $0.title, value: $0)
                        },
                        selection: appearanceBinding,
                        tint: accent
                    )
                    .font(AppType.ui(Typo.footnote, .medium))

                    Divider()

                    Text("强制浅色或深色后，颜色预设会自动切换到对应档位；桌面小组件仍跟随系统外观。")
                        .font(AppType.caption())
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                }

                settingsCard(title: "颜色主题", icon: "paintpalette") {
                    HStack(spacing: Space.l) {
                        ForEach(ColorPreset.allCases) { preset in
                            Button {
                                store.accentPreset = preset
                            } label: {
                                VStack(spacing: Space.s) {
                                    Circle()
                                        .fill(preset.color)
                                        .frame(width: 32, height: 32)
                                        .overlay(
                                            Circle().stroke(Color.primary.opacity(0.16), lineWidth: 1)
                                        )
                                        .overlay {
                                            if store.accentPreset == preset {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 13, weight: .bold))
                                                    .foregroundStyle(.white)
                                                    .shadow(color: .black.opacity(0.4), radius: 1)
                                            }
                                        }
                                        .shadow(color: preset.color.opacity(store.accentPreset == preset ? 0.35 : 0), radius: 6)
                                    Text(preset.title)
                                        .font(AppType.caption(12, weight: store.accentPreset == preset ? .semibold : .regular))
                                        .foregroundStyle(store.accentPreset == preset ? Color.primary : Color.secondary)
                                }
                            }
                            .buttonStyle(TimeSlotPressableStyle())
                            .contentShape(Rectangle())
                            .help(preset.title)
                            .accessibilityLabel(preset.title)
                            .accessibilityValue(store.accentPreset == preset ? "已选中" : "未选中")
                        }
                        Spacer(minLength: 0)
                    }

                    Divider()

                    Text("预设同时适配浅色与深色模式，改动立即生效。")
                        .font(AppType.caption())
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                }

                settingsCard(title: "桌面小组件", icon: "macwindow.on.rectangle") {
                    pickerRow(
                        label: "内容",
                        systemImage: "rectangle.split.2x1",
                        binding: widgetDisplayModeBinding
                    ) {
                        ForEach(WidgetDisplayMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }

                    Divider()

                    pickerRow(
                        label: "单位",
                        systemImage: "textformat.123",
                        binding: widgetTimeUnitBinding
                    ) {
                        Text("仅天数").tag("days")
                        Text("自动").tag("auto")
                        Text("仅小时").tag("hours")
                        Text("精细").tag("precise")
                    }

                    Text("添加“时隙 · 自定义”后，可在 macOS 的“编辑小组件”中为每个组件分别选择倒计时目标。")
                        .font(AppType.caption())
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)

                    Divider()

                    HStack(spacing: Space.m) {
                        Image(systemName: widgetSyncInfo.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(widgetSyncInfo.color)
                            .frame(width: 24, height: 24)
                            .background(
                                widgetSyncInfo.color.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                            )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(widgetSyncInfo.title)
                                .font(AppType.ui(Typo.footnote, .medium))
                            Text(widgetSyncInfo.subtitle)
                                .font(AppType.caption())
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: Space.m)
                        Button("立即刷新") {
                            store.refreshDesktopWidgets()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityIdentifier("timeslot.settings.widget.refresh")
                    }
                }

                settingsCard(title: "番茄钟节奏", icon: "timer") {
                    HStack {
                        settingLabel(
                            title: "当前节奏",
                            subtitle: rhythmSummary
                        )
                        Spacer()
                        Button("调整…") {
                            showingPomodoroSettings = true
                        }
                        .buttonStyle(.bordered)
                        .tint(accent)
                        .accessibilityIdentifier("timeslot.settings.pomodoro.edit")
                    }
                }

                settingsCard(title: "数据", icon: "externaldrive") {
                    HStack(spacing: Space.m) {
                        Image(systemName: storageMigrationIcon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(storageMigrationColor)
                            .frame(width: 24, height: 24)
                            .background(
                                storageMigrationColor.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                            )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(store.storageMigrationState.title)
                                .font(AppType.ui(Typo.footnote, .medium))
                            Text(store.storageMigrationState.subtitle)
                                .font(AppType.caption())
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                    }

                    Divider()

                    HStack {
                        settingLabel(
                            title: "阶段记录",
                            subtitle: "共 \(store.pomodoroHistory.count) 条，不足 10 秒的记录不会保留"
                        )
                        Spacer()
                        Button("清空…", role: .destructive) {
                            showingClearHistoryConfirmation = true
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("timeslot.settings.history.clear")
                    }

                    Divider()

                    HStack(spacing: Space.m) {
                        settingLabel(
                            title: "备份与恢复",
                            subtitle: "导出全部本地数据；导入前会自动保存一份当前数据"
                        )
                        Spacer(minLength: Space.m)
                        Button("导出…") { exportBackup() }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("timeslot.settings.backup.export")
                        Button("导入…") { chooseImportBackup() }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("timeslot.settings.backup.import")
                    }
                }

                settingsCard(title: "关于", icon: "info.circle") {
                    HStack {
                        settingLabel(
                            title: "时隙",
                            subtitle: appVersionText
                        )
                        Spacer()
                        Text("本地数据 · 无账户")
                            .font(AppType.caption(weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, Space.xxl)
            .padding(.top, Space.xxl)
            .padding(.bottom, Space.xxl)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Surface.canvas)
        .onAppear {
            store.refreshNotificationPermissionStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            store.refreshNotificationPermissionStatus()
        }
        .sheet(isPresented: $showingPomodoroSettings) {
            PomodoroSettingsView(state: store.pomodoro, accent: store.accentPreset.color) { focus, shortBreak, longBreak, rounds, weeklyGoalHours in
                store.updatePomodoroSettings(
                    focusMinutes: focus,
                    shortBreakMinutes: shortBreak,
                    longBreakMinutes: longBreak,
                    roundsBeforeLongBreak: rounds,
                    weeklyFocusGoalMinutes: weeklyGoalHours * 60
                )
            }
        }
        .alert("清空全部阶段记录？", isPresented: $showingClearHistoryConfirmation) {
            Button("清空全部", role: .destructive) {
                store.clearPomodoroHistory()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这会删除所有番茄钟和正计时历史记录；清空后可在 8 秒内撤销。当前计时和任务不会受影响。")
                .lineSpacing(2.5)
        }
        .alert(
            "导入备份？",
            isPresented: $showingImportConfirmation,
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
            Button("取消", role: .cancel) { pendingImport = nil }
        } message: { payload in
            Text("将导入 \(payload.items.count) 个倒计时、\(payload.history.count) 条阶段记录。当前数据会先自动备份，再被替换。")
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

    private func settingsCard<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            // 系统设置风格：圆角图标块 + 小节标题
            HStack(spacing: Space.s) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(accent)
                    .frame(width: 26, height: 26)
                    .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                Text(title)
                    .font(AppType.ui(Typo.body, .medium))
                    .tracking(Tracking.heading)
            }
            content()
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(
            cornerRadius: Radius.medium,
            borderOpacity: 0.07,
            shadowRadius: 8,
            shadowY: 2
        )
    }

    private func settingLabel(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(AppType.ui(Typo.footnote, .medium))
            Text(subtitle)
                .font(AppType.caption())
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private func pickerRow<SelectionValue: Hashable, Content: View>(
        label: String,
        systemImage: String,
        binding: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: Space.s) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(accent)
                .frame(width: 24, height: 24)
                .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(label)
                .font(AppType.ui(Typo.footnote, .medium))
            Spacer()
            Picker(label, selection: binding) {
                content()
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 110)
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

    private var notificationPermissionStatus: some View {
        let permission = store.notificationPermissionState
        return HStack(alignment: .top, spacing: Space.s) {
            Image(systemName: permission.systemImage)
                .font(AppType.ui(Typo.body, .medium))
                .foregroundStyle(notificationPermissionTint(for: permission))
                .frame(width: 28, height: 28)
                .background(
                    notificationPermissionTint(for: permission).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(permission.title)
                    .font(AppType.ui(Typo.footnote, .medium))
                Text(permission.detail)
                    .font(AppType.caption())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Space.s)

            switch permission {
            case .notDetermined:
                Button("允许通知") {
                    store.requestNotificationPermission()
                }
                .buttonStyle(.bordered)
                .tint(accent)
                .controlSize(.small)
                .accessibilityIdentifier("timeslot.settings.notifications.allow")
            case .denied:
                Button("打开系统设置") {
                    store.openNotificationSettings()
                }
                .buttonStyle(.bordered)
                .tint(accent)
                .controlSize(.small)
                .accessibilityIdentifier("timeslot.settings.notifications.open-system")
            case .checking:
                ProgressView()
                    .controlSize(.small)
            case .authorized, .provisional:
                EmptyView()
            }
        }
        .padding(Space.m)
        .background(Surface.nested, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
    }

    private func notificationPermissionTint(for state: NotificationPermissionState) -> Color {
        switch state {
        case .authorized, .provisional: return accent
        case .denied: return .orange
        case .checking, .notDetermined: return .secondary
        }
    }

    private var appearanceBinding: Binding<AppAppearance> {
        Binding(
            get: { store.appearanceMode },
            set: { newValue in
                guard newValue != store.appearanceMode else { return }
                store.appearanceMode = newValue
            }
        )
    }

    /// macOS 的 Picker 会在自身更新周期里回写 selection，
    /// 直接绑定 @Published 可能触发 “Publishing changes from within view updates”，
    /// 延迟到下一轮主队列更新 Store。
    private var widgetDisplayModeBinding: Binding<WidgetDisplayMode> {
        Binding(
            get: { store.widgetDisplayMode },
            set: { newValue in
                guard newValue != store.widgetDisplayMode else { return }
                DispatchQueue.main.async {
                    store.widgetDisplayMode = newValue
                }
            }
        )
    }

    private var widgetTimeUnitBinding: Binding<String> {
        Binding(
            get: { store.widgetTimeUnit },
            set: { newValue in
                guard newValue != store.widgetTimeUnit else { return }
                DispatchQueue.main.async {
                    store.widgetTimeUnit = newValue
                }
            }
        )
    }

    private var rhythmSummary: String {
        let state = store.pomodoro
        return "\(state.focusMinutes) 分钟专注 · \(state.shortBreakMinutes) 分钟短休息 · 每 \(state.roundsBeforeLongBreak) 轮进入 \(state.longBreakMinutes) 分钟长休息 · 周目标 \(max(1, state.weeklyFocusGoalMinutes / 60)) 小时"
    }

    private var widgetSyncInfo: (title: String, subtitle: String, icon: String, color: Color) {
        switch store.widgetSyncState {
        case .checking:
            return ("正在检查共享空间", "稍后会自动完成第一次同步", "arrow.triangle.2.circlepath", .secondary)
        case .ready(let date):
            let time = beijingDateString(date, dateStyle: .omitted, timeStyle: .shortened)
            return ("小组件同步正常", "最近同步于 \(time)", "checkmark.circle.fill", accent)
        case .unavailable:
            return ("共享空间不可用", "请重新安装当前版本以恢复小组件权限", "exclamationmark.triangle.fill", .orange)
        case .failed(let message):
            return ("小组件同步失败", message, "exclamationmark.circle.fill", .red)
        }
    }

    private var storageMigrationIcon: String {
        switch store.storageMigrationState {
        case .current: return "checkmark.shield.fill"
        case .migrated: return "arrow.up.circle.fill"
        case .pending: return "exclamationmark.triangle.fill"
        }
    }

    private var storageMigrationColor: Color {
        switch store.storageMigrationState {
        case .current: return accent
        case .migrated: return .blue
        case .pending: return .orange
        }
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
            showingImportConfirmation = true
        } catch {
            operationError = error.localizedDescription
        }
    }

    private var appVersionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return "版本 \(version) (\(build))"
    }
}
