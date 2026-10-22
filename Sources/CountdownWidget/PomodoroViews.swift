import AppKit
import Charts
import Combine
import SwiftUI

/// Export uses saved focus sessions only; paused wall time is apportioned across overlaps.
private struct StudyShareSheet: View {
    let records: [PomodoroSessionRecord]
    @Environment(\.dismiss) private var dismiss
    @State private var range = "今天"
    @State private var start = Date()
    @State private var end = Date()
    @State private var errorMessage: String?
    @State private var saved = false
    @AppStorage("studyShareHideSubjects", store: countdownDefaults) private var hideSubjects = false
    @State private var copied = false

    private func durationText(_ seconds: Double) -> String {
        let minutes = max(0, Int(seconds) / 60)
        if seconds > 0 && minutes == 0 { return "不足 1 分钟" }
        if minutes < 60 { return "\(minutes) 分钟" }
        return minutes % 60 == 0 ? "\(minutes / 60) 小时" : "\(minutes / 60) 小时 \(minutes % 60) 分"
    }

    private var dateCaption: String {
        let first = beijingDateString(bounds.0, dateStyle: .abbreviated, timeStyle: .omitted)
        let last = bounds.1.addingTimeInterval(-1)
        return beijingCalendar.isDate(bounds.0, inSameDayAs: last) ? first
            : first + " — " + beijingDateString(last, dateStyle: .abbreviated, timeStyle: .omitted)
    }

    private var exportFilename: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = beijingCalendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let first = formatter.string(from: bounds.0)
        let last = formatter.string(from: bounds.1.addingTimeInterval(-1))
        return "时隙学习记录-" + first + (first == last ? "" : "至" + last) + ".png"
    }

    private var bounds: (Date, Date) {
        let calendar = beijingCalendar
        let today = calendar.startOfDay(for: Date())
        let first = range == "今天" ? today : range == "本周"
            ? PomodoroHistoryRangePolicy.weekStart(containing: Date())
            : calendar.startOfDay(for: min(start, end))
        let last = range == "自选日期" ? calendar.startOfDay(for: max(start, end)) : today
        return (first, calendar.date(byAdding: .day, value: 1, to: last)!)
    }

    private var summary: (tasks: [(String, Double)], hours: [Double], days: [Date: Double], count: Int) {
        let (from, to) = bounds
        let slices = FocusStats.slices(in: records, from: from, to: to)
        var tasks: [String: Double] = [:]
        var hours = Array(repeating: 0.0, count: 24)
        var days: [Date: Double] = [:]
        for slice in slices {
            tasks[slice.taskTitle, default: 0] += slice.duration
            if slice.hour >= 0 && slice.hour < 24 {
                hours[slice.hour] += slice.duration
            }
            days[slice.day, default: 0] += slice.duration
        }
        let count = Set(
            records.filter { FocusStats.isSavedFocus($0) && $0.endedAt > from && $0.startedAt < to }.map(\.id)
        ).count
        return (
            tasks.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.map { ($0.key, $0.value) },
            hours,
            days,
            count
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("学习记录分享图").font(.system(size: 20, weight: .semibold))
                    Text("选择日期，预览后复制或保存图片")
                        .font(AppType.ui(Typo.footnote)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").frame(width: 20, height: 20)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("关闭")
                .help("关闭（Esc）")
                .keyboardShortcut(.cancelAction)
            }
            .padding(24)
            VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("日期范围").font(AppType.ui(Typo.footnote, .medium))
                Spacer()
            Picker("日期范围", selection: $range) {
                ForEach(["今天", "本周", "自选日期"], id: \.self) { Text($0) }
            }.pickerStyle(.segmented).labelsHidden().frame(width: 280)
            }
            if range == "自选日期" {
                HStack {
                    DatePicker("从", selection: $start, displayedComponents: .date)
                    DatePicker("至", selection: $end, displayedComponents: .date)
                }.environment(\.timeZone, beijingCalendar.timeZone)
            }
            Toggle(isOn: $hideSubjects) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("隐藏科目明细").font(AppType.ui(Typo.footnote, .medium))
                    Text("仅分享总时长和投入图").font(AppType.caption()).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.toggleStyle(.switch).controlSize(.small)
                .accessibilityLabel("隐藏科目明细")
            }
            .padding(.horizontal, 24).padding(.bottom, 18)
            Divider()
            ScrollView {
                shareCard
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.primary.opacity(0.04))
            Divider()
            HStack {
                Label(copied ? "已复制，可粘贴到聊天" : saved ? "图片已保存" : "仅统计已保存记录",
                      systemImage: copied || saved ? "checkmark.circle" : "info.circle")
                    .font(AppType.caption()).foregroundStyle(.secondary)
                Spacer()
                Button { copyImage() } label: { Label("复制图片", systemImage: "doc.on.doc") }
                Button { save() } label: { Label("保存 PNG…", systemImage: "square.and.arrow.down") }
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)
            .padding(.horizontal, 24).padding(.vertical, 16)
        }
        .frame(width: 640, height: 650)
        .onChange(of: range) { saved = false; copied = false }
        .onChange(of: start) { saved = false; copied = false }
        .onChange(of: end) { saved = false; copied = false }
        .onChange(of: hideSubjects) { saved = false; copied = false }
        .alert("导出失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private var shareCard: some View {
        let data = summary
        let total = data.tasks.reduce(0) { $0 + $1.1 }
        let teal = Color(red: 0.16, green: 0.48, blue: 0.46)
        return VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text("TIMESLOT / 学习记录").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("专注积累，每天一点").font(.system(size: 11))
            }.foregroundStyle(teal)
            Text(dateCaption)
                .font(.system(size: 14)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                Text(durationText(total))
                    .font(.system(size: 38, weight: .medium, design: .rounded))
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text("完成 \(data.count) 次学习记录 · 北京时间")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
            Divider()
            if !hideSubjects {
            Text("科目投入").font(.system(size: 15, weight: .semibold))
            if data.tasks.isEmpty {
                Text("这段时间还没有已保存的学习记录")
                    .font(.system(size: 14)).foregroundStyle(.secondary)
            }
            ForEach(Array(data.tasks.enumerated()), id: \.offset) { _, task in
                VStack(spacing: 6) {
                    HStack {
                        Text(task.0).lineLimit(2)
                        Spacer()
                        Text(durationText(task.1) + " · \(Int((task.1 / max(total, 1) * 100).rounded()))%")
                            .fixedSize(horizontal: true, vertical: false)
                    }.font(.system(size: 13))
                    GeometryReader { proxy in
                        Capsule().fill(teal.opacity(0.10))
                        Capsule().fill(teal).frame(width: proxy.size.width * task.1 / max(total, 1))
                    }.frame(height: 5)
                }
            }
            }
            if range == "本周" || !beijingCalendar.isDate(bounds.0, inSameDayAs: bounds.1.addingTimeInterval(-1)) {
                dailyChart(days: data.days, tint: teal)
            } else {
            Text("学习时段 · 按小时累计").font(.system(size: 15, weight: .semibold))
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(0..<24, id: \.self) { hour in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(data.hours[hour] > 0 ? teal : teal.opacity(0.10))
                        .frame(height: max(3, 76 * data.hours[hour] / max(1, data.hours.max() ?? 1)))
                }
            }.frame(height: 76, alignment: .bottom)
            HStack { Text("00:00"); Spacer(); Text("12:00"); Spacer(); Text("24:00") }
                .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Text("由时隙生成 · 番茄钟与正计时的已保存专注记录")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .padding(32).frame(width: 552)
        .background(Color(red: 0.97, green: 0.98, blue: 0.98))
        .environment(\.colorScheme, .light)
    }

    private func dailyChart(days: [Date: Double], tint: Color) -> some View {
        let count = range == "本周" ? 7 : max(1, beijingCalendar.dateComponents([.day], from: bounds.0, to: bounds.1).day ?? 1)
        // Keep long custom ranges readable and bounded by grouping them into at most 31 bars.
        let step = max(1, Int(ceil(Double(count) / 31)))
        let points = stride(from: 0, to: count, by: step).map { offset -> (date: Date, hours: Double) in
            let date = beijingCalendar.date(byAdding: .day, value: offset, to: bounds.0)!
            let next = beijingCalendar.date(byAdding: .day, value: min(step, count - offset), to: date)!
            return (date, days.filter { $0.key >= date && $0.key < next }.values.reduce(0, +) / 3600)
        }
        return VStack(alignment: .leading, spacing: 14) {
            Text(step == 1 ? "每日投入" : "每日投入 · 每 \(step) 天合计")
                .font(.system(size: 15, weight: .semibold))
            Chart(points, id: \.date) { point in
                BarMark(x: .value("日期", point.date, unit: .day), y: .value("小时", point.hours))
                    .foregroundStyle(tint).cornerRadius(3)
            }
            .chartYScale(domain: 0...max(1, (points.map(\.hours).max() ?? 0) * 1.2))
            .chartYAxis { AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(Surface.gridLine)
                AxisValueLabel { if let hours = value.as(Double.self) { Text(String(format: "%g h", hours)) } }
            } }
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: min(count, 7))) { value in
                AxisValueLabel(format: range == "本周" ? .dateTime.weekday(.abbreviated) : .dateTime.month(.defaultDigits).day())
            } }
            .frame(height: 140)
        }
        .environment(\.calendar, beijingCalendar)
        .environment(\.timeZone, beijingCalendar.timeZone)
        .environment(\.locale, Locale(identifier: "zh_CN"))
    }

    @MainActor private func pngData() -> Data? {
        let renderer = ImageRenderer(content: shareCard)
        renderer.scale = 2
        guard let image = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            errorMessage = "无法生成图片，请重试。"
            return nil
        }
        return png
    }

    @MainActor private func copyImage() {
        guard let png = pngData() else { return }
        NSPasteboard.general.clearContents()
        if NSPasteboard.general.setData(png, forType: .png) {
            copied = true; saved = false
        } else { errorMessage = "无法复制图片，请尝试保存 PNG。" }
    }

    @MainActor private func save() {
        guard let png = pngData() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = exportFilename
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try png.write(to: url, options: .atomic)
            saved = true
            copied = false
        } catch { errorMessage = error.localizedDescription }
    }
}

enum PomodoroOpenRequest: Equatable {
    case todayInsights
}

struct PomodoroView: View {
    private enum PresentedSheet: String, Identifiable {
        case tasks
        case settings
        case weeklyGoal
        case share

        var id: String { rawValue }
    }

    private enum Workspace: String, CaseIterable, Identifiable {
        case focus
        case insights

        var id: String { rawValue }

        var title: String {
            switch self {
            case .focus: return "专注"
            case .insights: return "统计"
            }
        }

        var systemImage: String {
            switch self {
            case .focus: return "timer"
            case .insights: return "chart.xyaxis.line"
            }
        }
    }

    @ObservedObject var store: CountdownStore
    let onSyncWidget: () -> Void
    @Binding var openRequest: PomodoroOpenRequest?
    @State private var presentedSheet: PresentedSheet?
    @State private var historyRange: PomodoroHistoryRange
    @State private var customHistoryStart: Date
    @State private var customHistoryEnd: Date
    @State private var selectedWeekStart: Date
    @State private var showingAllHistory = false
    @State private var showingClearHistoryConfirmation = false
    @State private var editingRecord: PomodoroSessionRecord?
    @State private var showingResetConfirmation = false
    @State private var timerMode: PomodoroTimerMode
    @State private var workspace: Workspace = .focus
    @State private var selectedTrendDate: Date?
    @State private var showingRecordDetails = true
    @State private var recordsFollowAnalysis = true
    @State private var analysisDays = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    /// 睡眠跨过零点后回到前台时，用它迫使统计页按当前时钟重算。
    @State private var focusClock = Date.distantPast

    init(
        store: CountdownStore,
        onSyncWidget: @escaping () -> Void,
        openRequest: Binding<PomodoroOpenRequest?>
    ) {
        self.store = store
        self.onSyncWidget = onSyncWidget
        self._openRequest = openRequest
        // 统计页默认看今天。不再沿用以前存下来的「按周」，避免和今日统计各算各的。
        _historyRange = State(initialValue: .today)
        _customHistoryStart = State(
            initialValue: beijingCalendar.date(byAdding: .day, value: -6, to: Date()) ?? Date()
        )
        _customHistoryEnd = State(initialValue: Date())
        _selectedWeekStart = State(
            initialValue: PomodoroHistoryRangePolicy.weekStart(containing: Date())
        )
        let storedMode = countdownDefaults
            .string(forKey: "pomodoroTimerMode")
            .flatMap(PomodoroTimerMode.init(rawValue:))
        // 未结束的会话优先于上次浏览偏好，避免重启后显示另一种计时器。
        _timerMode = State(
            initialValue: PomodoroTimerModePolicy.initialMode(
                storedMode: storedMode,
                state: store.pomodoro
            )
        )
    }

    private var state: PomodoroState { store.pomodoro }
    private var accent: Color { store.accentPreset.color }

    private func phaseColor(for phase: PomodoroPhase) -> Color {
        let preset = store.accentPreset
        switch phase {
        case .focus: return accent
        case .shortBreak: return Color(hex: preset.breakHex)
        case .longBreak: return Color(hex: preset.longBreakHex)
        }
    }

    private var phaseColor: Color { phaseColor(for: state.phase) }
    private var stopwatchColor: Color { accent }

    // 这些范围都是「天」的粒度。外层 BeijingDaySchedule 在北京时间零点重绘这一页，不需要每秒重算。
    private var historyBounds: (start: Date, end: Date)? {
        if recordsFollowAnalysis {
            return FocusStats.trailingDayWindow(days: analysisDays)
        }
        guard let bounds = PomodoroHistoryRangePolicy.bounds(
            for: historyRange,
            now: Date(),
            selectedWeekStart: selectedWeekStart,
            customStart: customHistoryStart,
            customEnd: customHistoryEnd
        ) else { return nil }
        return (bounds.start, bounds.end)
    }

    private var availableWeekStarts: [Date] {
        PomodoroHistoryRangePolicy.availableWeekStarts(
            recordDates: store.pomodoroHistory.map(\.startedAt),
            now: Date()
        )
    }

    private var filteredHistoryRecords: [PomodoroSessionRecord] {
        guard let bounds = historyBounds else { return store.pomodoroHistory }
        return store.pomodoroHistory.filter { record in
            record.endedAt > bounds.start && record.startedAt < bounds.end
        }
    }

    private var dailyFocusPoints: [PomodoroDailyFocusPoint] {
        FocusStats.dailyTaskPoints(
            in: store.pomodoroHistory,
            from: historyBounds?.start,
            to: historyBounds?.end
        )
    }

    /// 图例和配色的稳定顺序：按该范围内的专注总时长排，长的在前。
    private func taskOrder(in points: [PomodoroDailyFocusPoint]) -> [String] {
        var totals: [String: TimeInterval] = [:]
        for point in points {
            totals[point.taskTitle, default: 0] += point.duration
        }
        return totals.sorted { lhs, rhs in
            lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
        }.map(\.key)
    }

    /// 「按任务分布」用的合计，跟历史列表一样按所选范围裁剪时长。
    private var taskBreakdown: [(title: String, duration: TimeInterval)] {
        var totals: [String: TimeInterval] = [:]
        for record in filteredHistoryRecords where record.phase == .focus {
            let title = PomodoroTaskPalette.normalized(record.taskTitle)
            totals[title, default: 0] += displayedDuration(for: record)
        }
        return totals
            .filter { $0.value > 0 }
            .map { (title: $0.key, duration: $0.value) }
            .sorted { lhs, rhs in
                lhs.duration == rhs.duration ? lhs.title < rhs.title : lhs.duration > rhs.duration
            }
    }

    var body: some View {
        TimelineView(BeijingDaySchedule()) { context in
            let _ = FocusStats.displayInstant(scheduleDate: context.date, anchor: focusClock)
            focusPage
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                focusClock = Date()
            }
        }
    }

    private var focusPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("专注")
                        .font(AppType.caption())
                        .foregroundStyle(.secondary)
                    Text(state.taskTitle.isEmpty ? "专注当前任务" : state.taskTitle)
                        .font(AppType.pageTitle(28))
                        .tracking(-0.4)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    presentedSheet = .share
                } label: {
                    Label("分享记录", systemImage: "square.and.arrow.up")
                        .font(AppType.ui(Typo.footnote, .medium))
                        .padding(8)
                }
                .buttonStyle(TimeSlotPressableStyle())
                .inkPill()
                .accessibilityIdentifier("timeslot.pomodoro.share")
                HStack(spacing: Space.s) {
                    Circle()
                        .fill(
                            (timerMode == .stopwatch ? state.stopwatchRunning : state.isRunning)
                            ? Color.primary
                            : Color.secondary.opacity(0.42)
                        )
                        .frame(width: 6, height: 6)
                    Text(timerMode == .stopwatch ? stopwatchStatusTitle : timerStatusTitle)
                        .font(AppType.caption(weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, Space.s)
                .padding(.vertical, Space.xs)
                .background(Surface.nested, in: Capsule())

                Button {
                    presentedSheet = .tasks
                } label: {
                    Label("任务", systemImage: "checklist")
                        .font(AppType.ui(Typo.footnote, .medium))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .foregroundStyle(.primary.opacity(0.78))
                }
                .buttonStyle(TimeSlotPressableStyle())
                .inkPill()
                .accessibilityIdentifier("timeslot.pomodoro.tasks")

                Button(action: onSyncWidget) {
                    Label("设为小组件内容", systemImage: "rectangle.3.group")
                        .font(AppType.ui(Typo.footnote, .medium))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .foregroundStyle(.primary.opacity(0.78))
                }
                .buttonStyle(TimeSlotPressableStyle())
                .inkPill()
                .accessibilityIdentifier("timeslot.pomodoro.widget-sync")
            }
            .padding(.horizontal, Space.xxl)
            .padding(.top, Space.xxl)
            .padding(.bottom, Space.l)

            TimeSlotSegmentedControl(
                options: Workspace.allCases.map {
                    SegmentOption(
                        id: "pomodoro.\($0.id)",
                        title: $0.title,
                        systemImage: $0.systemImage,
                        value: $0
                    )
                },
                selection: $workspace,
                tint: timerMode == .stopwatch ? stopwatchColor : phaseColor
            )
            .frame(width: 220)
            .padding(.horizontal, Space.xxl)
            .padding(.bottom, Space.l)

            workspaceContent
        }
        .sheet(item: $editingRecord) { record in
            PomodoroHistoryEditSheet(
                record: record,
                tasks: store.pomodoroTasks,
                phaseTitle: record.phase.title
            ) { startedAt, endedAt, taskTitle in
                store.updatePomodoroHistoryRecord(
                    id: record.id,
                    startedAt: startedAt,
                    endedAt: endedAt,
                    taskTitle: taskTitle
                )
            }
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .share:
                StudyShareSheet(records: store.pomodoroHistory)
            case .weeklyGoal:
                WeeklyGoalSettingsView(
                    goalHours: max(1, state.weeklyFocusGoalMinutes / 60),
                    accent: store.accentPreset.color
                ) { hours in
                    store.updateWeeklyFocusGoal(hours: hours)
                }
            case .settings:
                PomodoroSettingsView(
                    state: state,
                    accent: store.accentPreset.color,
                    breakAccent: Color(hex: store.accentPreset.breakHex),
                    longBreakAccent: Color(hex: store.accentPreset.longBreakHex)
                ) { focus, shortBreak, longBreak, rounds, weeklyGoalHours in
                    store.updatePomodoroSettings(
                        focusMinutes: focus,
                        shortBreakMinutes: shortBreak,
                        longBreakMinutes: longBreak,
                        roundsBeforeLongBreak: rounds,
                        weeklyFocusGoalMinutes: weeklyGoalHours * 60
                    )
                }
            case .tasks:
                PomodoroTasksView(
                    tasks: store.pomodoroTasks,
                    selectedTitle: state.taskTitle,
                    canSwitch: store.canSwitchPomodoroTask,
                    onSelect: store.selectPomodoroTask,
                    onAdd: store.addPomodoroTask,
                    onDelete: store.deletePomodoroTask
                )
            }
        }
        .alert("清空全部阶段记录？", isPresented: $showingClearHistoryConfirmation) {
            Button("清空全部", role: .destructive) {
                store.clearPomodoroHistory()
                showingAllHistory = false
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这会删除所有番茄钟和正计时历史记录；清空后可在 8 秒内撤销。当前计时和任务不会受影响。")
                .lineSpacing(2.5)
        }
        .alert("重置当前计时？", isPresented: $showingResetConfirmation) {
            Button("重置", role: .destructive) {
                resetTimer()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("当前计时不会写入阶段记录，已用时也会被清除。")
        }
        .onChange(of: historyRange) {
            showingAllHistory = false
            selectedTrendDate = nil
        }
        .onChange(of: analysisDays) {
            guard recordsFollowAnalysis else { return }
            alignRecordsWithAnalysis()
        }
        .onAppear { consumeOpenRequest() }
        .onChange(of: openRequest) { consumeOpenRequest() }
        .onChange(of: selectedWeekStart) {
            showingAllHistory = false
            selectedTrendDate = nil
        }
        .onChange(of: customHistoryStart) { selectedTrendDate = nil }
        .onChange(of: customHistoryEnd) { selectedTrendDate = nil }
        .onChange(of: timerMode) { _, newMode in
            countdownDefaults.set(newMode.rawValue, forKey: "pomodoroTimerMode")
        }
        .onReceive(NotificationCenter.default.publisher(for: .openPomodoroSettingsRequested)) { _ in
            presentedSheet = .settings
        }
    }

    @ViewBuilder
    private var workspaceContent: some View {
        switch workspace {
        case .focus:
            ScrollView {
                focusWorkspace
                    .frame(maxWidth: 1040)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, Space.xxl)
                    .padding(.bottom, Space.xxl)
            }
            .scrollIndicators(.hidden)
            .accessibilityIdentifier("timeslot.pomodoro.focus-workspace")
        case .insights:
            ScrollView {
                historyCard
                    .frame(maxWidth: 1040)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, Space.xxl)
                    .padding(.bottom, Space.xxl)
            }
            .scrollIndicators(.hidden)
            .accessibilityIdentifier("timeslot.pomodoro.insights-workspace")
        }
    }

    private var focusWorkspace: some View {
        HStack(alignment: .top, spacing: 0) {
            timerCard
                .frame(maxWidth: .infinity)

            Divider()
                .padding(.vertical, Space.xl)

            infoPanel
                .frame(width: 272)
        }
        .padding(.vertical, Space.m)
    }

    /// 右侧合并信息面板：任务、本组进度、节奏摘要，用分隔线分区，不各占一张卡。
    private var infoPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            compactTaskSection

            Divider()
                .padding(.vertical, Space.m)

            if timerMode == .countdown {
                compactSessionSection
                Divider()
                    .padding(.vertical, Space.m)
                compactRhythmSection
            } else {
                stopwatchInfoSection
            }
        }
        .padding(.vertical, Space.xl)
        .padding(.horizontal, Space.l)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var compactTaskSection: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                Text("当前任务")
                    .font(AppType.ui(Typo.footnote, .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    presentedSheet = .tasks
                } label: {
                    Image(systemName: "ellipsis")
                        .font(AppType.caption(12, weight: .semibold))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(TimeSlotPressableStyle())
                .help("管理任务")
                .accessibilityLabel("管理任务")
            }

            Picker(
                "当前任务",
                selection: Binding(
                    get: {
                        store.pomodoroTasks.first(where: { $0.title == state.taskTitle })?.id
                            ?? store.pomodoroTasks.first?.id
                    },
                    set: { selectedID in
                        guard let selectedID else { return }
                        DispatchQueue.main.async {
                            store.selectPomodoroTask(selectedID)
                        }
                    }
                )
            ) {
                ForEach(store.pomodoroTasks) { task in
                    Text(task.title).tag(Optional(task.id))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .font(AppType.ui(Typo.footnote, .medium))
            .disabled(!store.canSwitchPomodoroTask)

            if !store.canSwitchPomodoroTask {
                Label(
                    state.isRunning ? "计时中不可切换任务" : "停止并记录后可切换",
                    systemImage: "lock.fill"
                )
                .font(AppType.caption(weight: .medium))
                .foregroundStyle(.secondary)
            }
        }
    }

    private var compactSessionSection: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack {
                Text("本组进度")
                    .font(AppType.ui(Typo.footnote, .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("累计完成 \(state.completedFocusSessions) 个番茄")
                    .font(AppType.caption(11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                ForEach(0..<state.roundsBeforeLongBreak, id: \.self) { index in
                    let completedInCycle = state.completedFocusSessions % state.roundsBeforeLongBreak
                    let isDone = index < completedInCycle
                    Capsule()
                        .fill(isDone ? Color.primary.opacity(0.72) : Surface.track)
                        .frame(maxWidth: .infinity)
                        .frame(height: 8)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("本组番茄进度")
            .accessibilityValue("当前组已完成 \(state.completedFocusSessions % state.roundsBeforeLongBreak) / \(state.roundsBeforeLongBreak) 个番茄")
        }
    }

    private var compactRhythmSection: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                Text("节奏")
                    .font(AppType.ui(Typo.footnote, .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    presentedSheet = .settings
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(AppType.caption(12, weight: .semibold))
                        .contentShape(Rectangle())
                }
                .buttonStyle(TimeSlotPressableStyle())
                .help("调整完整设置")
                .accessibilityLabel("调整完整设置")
            }

            Text("\(state.focusMinutes) 分专注 · \(state.shortBreakMinutes) 分短休 · 每 \(state.roundsBeforeLongBreak) 轮 \(state.longBreakMinutes) 分长休")
                .font(AppType.ui(Typo.footnote))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var stopwatchInfoSection: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("本次正计时")
                .font(AppType.ui(Typo.footnote, .medium))
                .foregroundStyle(.secondary)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("开始于")
                        .font(AppType.caption())
                        .foregroundStyle(.secondary)
                    Text(startedAtText)
                        .font(AppType.ui(Typo.body, .medium))
                        .monospacedDigit()
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("今日正计时")
                        .font(AppType.caption())
                        .foregroundStyle(.secondary)
                    Text(todayRecordsSummary)
                        .font(AppType.ui(Typo.body, .medium))
                        .foregroundStyle(Color.primary)
                }
            }
            Text(state.stopwatchRunning ? "正在计时" : "已暂停")
                .font(AppType.caption())
                .foregroundStyle(.secondary)
        }
    }

    private var todayRecordsSummary: String {
        let bounds = FocusStats.todayBounds()
        let overlap = FocusStats.stopwatchOverlap(
            in: store.pomodoroHistory,
            from: bounds.start,
            to: bounds.end
        )
        if overlap.count == 0 { return "尚无记录" }
        return "\(overlap.count) 次 · \(formatHistoryDuration(overlap.seconds))"
    }
    /// 正计时模式右侧的信息卡：本次开始时间、今日累计与最近记录。
    /// 实时秒数由 timerCard 的大数字承担，这里只放不重复的静态信息。
    private var todayStopwatchRecords: [PomodoroSessionRecord] {
        store.pomodoroHistory.filter { record in
            record.status == .stopwatch && beijingCalendar.isDateInToday(record.startedAt)
        }
    }

    private var startedAtText: String {
        guard let start = state.stopwatchSessionStartedAt else { return "尚未开始" }
        // 与全应用的北京时间约定保持一致，避免正计时的「开始于」落在系统时区。
        return beijingDateString(start, dateStyle: .omitted, timeStyle: .shortened)
    }

    private var timerCard: some View {
        VStack(spacing: Space.l) {
            TimeSlotSegmentedControl(
                options: PomodoroTimerMode.allCases.map {
                    SegmentOption(
                        id: $0.id,
                        title: $0.title,
                        systemImage: $0.icon,
                        value: $0
                    )
                },
                selection: $timerMode,
                tint: stopwatchColor
            )
            .font(AppType.ui(Typo.footnote, .medium))
            .frame(width: 240)
            .disabled(!PomodoroTimerModePolicy.canSwitchMode(for: state))
            .help(
                PomodoroTimerModePolicy.canSwitchMode(for: state)
                    ? "切换计时方式"
                    : "停止或重置当前计时后可切换"
            )

            if timerMode == .countdown && !state.isRunning {
                quickPresetPills
            }

            let timerIsRunning = timerMode == .stopwatch ? state.stopwatchRunning : state.isRunning
            Group {
                if timerIsRunning {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        timerMeter(at: context.date)
                    }
                } else {
                    // 暂停/等待时读数不会变化，静态渲染可避免番茄钟页面空转。
                    timerMeter(at: Date())
                }
            }
            .padding(.vertical, Space.m)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                timerMode == .stopwatch
                    ? "正计时，已计时 \(stopwatchTimeText(state.stopwatchElapsed(at: Date())))"
                    : "\(state.phase.title)，剩余 \(timeText(state.remaining(at: Date())))"
            )

            HStack(spacing: 8) {
                Button {
                    if isTimerActive {
                        showingResetConfirmation = true
                    } else {
                        resetTimer()
                    }
                } label: {
                    Label("重置", systemImage: "arrow.counterclockwise")
                        .font(AppType.ui(Typo.footnote, .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .foregroundStyle(.primary.opacity(0.72))
                }
                .buttonStyle(TimeSlotPressableStyle())
                .inkPill()
                .help(isTimerActive ? "重置会清除当前计时" : "重置计时")
                .accessibilityIdentifier("timeslot.pomodoro.reset")

                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.75)) {
                        if timerMode == .stopwatch {
                            store.startOrPauseStopwatch()
                        } else {
                            store.startOrPausePomodoro()
                        }
                    }
                } label: {
                    let isLive = timerMode == .stopwatch ? state.stopwatchRunning : state.isRunning
                    Label(
                        isLive ? "暂停" : "开始",
                        systemImage: isLive ? "pause.fill" : "play.fill"
                    )
                    .font(AppType.ui(Typo.body, .semibold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                }
                // 开始/暂停是全应用唯一的实心主行动，重置/停止保持幽灵样式。
                .buttonStyle(TimeSlotPrimaryActionStyle())
                .accessibilityIdentifier("timeslot.pomodoro.start-pause")

                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7)) {
                        if timerMode == .stopwatch {
                            store.stopStopwatch()
                        } else {
                            store.stopPomodoro()
                        }
                    }
                } label: {
                    Label("结束并记录", systemImage: "stop.fill")
                        .font(AppType.ui(Typo.footnote, .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .foregroundStyle(.primary.opacity(0.72))
                }
                .buttonStyle(TimeSlotPressableStyle())
                .inkPill()
                .accessibilityIdentifier("timeslot.pomodoro.stop")
                .disabled(
                    timerMode == .stopwatch
                        ? !state.isStopwatchActive
                        : state.sessionStartedAt == nil
                )
                .help("结束当前计时。实际用时满 10 秒才写入学习记录，不足 10 秒不会写入。重置不记录。")

                if timerMode == .countdown {
                    Button {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7)) {
                            store.skipPomodoroPhase()
                        }
                    } label: {
                        Image(systemName: "forward.end.fill")
                            .font(AppType.ui(Typo.footnote, .medium))
                            .frame(width: 28, height: 28)
                            .foregroundStyle(.primary.opacity(0.55))
                    }
                    .buttonStyle(TimeSlotPressableStyle())
                    .help("跳过当前阶段")
                    .accessibilityLabel("跳过当前阶段")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.xl)
    }

    private var quickPresetPills: some View {
        HStack(spacing: 6) {
            ForEach(PomodoroPresets.quick(for: state.phase), id: \.self) { mins in
                let isCurrent = Int(state.duration(for: state.phase) / 60) == mins
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        store.updateCurrentPomodoroPhaseDuration(minutes: mins)
                    }
                } label: {
                    Text("\(mins)分")
                        .font(AppType.caption(12, weight: isCurrent ? .semibold : .regular))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(isCurrent ? Color.primary.opacity(0.08) : Surface.nested, in: Capsule())
                        .foregroundStyle(isCurrent ? Color.primary : Color.secondary)
                }
                .buttonStyle(TimeSlotPressableStyle())
                .disabled(state.isRunning)
            }
        }
    }
    private var historyCard: some View {
        let records = filteredHistoryRecords.sorted { $0.startedAt > $1.startedAt }
        let visibleRecords = showingAllHistory ? records : Array(records.prefix(8))
        let groupedRecords = Dictionary(grouping: visibleRecords) { beijingCalendar.startOfDay(for: $0.startedAt) }
        let focusTotal = records.filter { $0.phase == .focus }.reduce(0.0) { $0 + displayedDuration(for: $1) }
        let shortBreakTotal = records.filter { $0.phase == .shortBreak }.reduce(0.0) { $0 + displayedDuration(for: $1) }
        let longBreakTotal = records.filter { $0.phase == .longBreak }.reduce(0.0) { $0 + displayedDuration(for: $1) }

        return VStack(alignment: .leading, spacing: 20) {
            FocusAnalysisWorkspace(
                records: store.pomodoroHistory,
                tint: accent,
                taskColor: { store.taskColor(for: $0) },
                days: $analysisDays,
                showsHeader: false,
                now: beijingCalendar.startOfDay(for: Date())
            )

            weeklyGoalCard

            DisclosureGroup("学习记录", isExpanded: $showingRecordDetails) {
            HStack {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(recordsFollowAnalysis ? "学习记录 · 与上方统计同一范围" : "学习记录 · 独立范围")
                        .font(AppType.title(15))
                        .tracking(0.2)
                    Text(recordsScopeNote)
                        .font(AppType.ui(Typo.footnote))
                        .foregroundStyle(Color.primary.opacity(0.72))
                }
                Spacer()
                if !recordsFollowAnalysis {
                    Button("改回与统计相同") {
                        recordsFollowAnalysis = true
                        alignRecordsWithAnalysis()
                    }
                    .buttonStyle(.borderless)
                }
                if !records.isEmpty {
                    Button("清空全部", role: .destructive) {
                        showingClearHistoryConfirmation = true
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("timeslot.pomodoro.history.clear")
                }
            }

            historyFilter

            HStack {
                Text("所选范围：\(historyRangeSummary)")
                    .font(AppType.caption())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(records.count) 条记录")
                    .font(AppType.caption(weight: .medium))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 0) {
                PomodoroTotalCell(label: "专注总计", value: formatHistoryDuration(focusTotal), color: phaseColor(for: .focus))
                Divider().frame(height: 42)
                PomodoroTotalCell(label: "短休息", value: formatHistoryDuration(shortBreakTotal), color: phaseColor(for: .shortBreak))
                Divider().frame(height: 42)
                PomodoroTotalCell(label: "长休息", value: formatHistoryDuration(longBreakTotal), color: phaseColor(for: .longBreak))
            }
            .padding(.vertical, Space.m)
            .nestedSurface()

            if records.isEmpty {
                HStack(spacing: Space.m) {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(.secondary)
                    Text("完成一个阶段后，这里会显示它的实际时长和时间。")
                        .font(AppType.ui(Typo.footnote))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, Space.s)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(groupedRecords.keys.sorted(by: >), id: \.self) { day in
                        Text(beijingDateString(day, dateStyle: .complete, timeStyle: .omitted))
                            .font(AppType.ui(Typo.footnote, .semibold))
                            .padding(.top, Space.l).padding(.bottom, Space.s)
                    ForEach(groupedRecords[day] ?? []) { record in
                        HStack(spacing: Space.m) {
                        PomodoroHistoryRow(
                            record: record,
                            displayedDuration: displayedDuration(for: record),
                            taskColor: store.taskColor(for: record.taskTitle)
                        )
                        Button { editingRecord = record } label: {
                            Image(systemName: "pencil").frame(width: 28, height: 28)
                        }
                        .buttonStyle(.borderless)
                        .help("修正记录")
                        .accessibilityLabel("修正\(record.taskTitle)的记录")
                        }
                        .contextMenu {
                            Button("修正记录…", systemImage: "slider.horizontal.3") {
                                editingRecord = record
                            }
                            Button("删除这条记录", role: .destructive) {
                                store.deletePomodoroHistory(ids: [record.id], title: record.taskTitle)
                            }
                        }
                        Divider().padding(.leading, 42)
                    }
                    }
                }

                if records.count > 8 {
                    Button {
                        // 大量历史行在 ScrollView 中做高度动画会让 AppKit 短暂计算出
                        // 负尺寸并产生运行时故障；直接切换既稳定也更利落。
                        showingAllHistory.toggle()
                    } label: {
                        Label(
                            showingAllHistory ? "收起记录" : "查看全部 \(records.count) 条",
                            systemImage: showingAllHistory ? "chevron.up" : "chevron.down"
                        )
                        .font(AppType.ui(Typo.footnote, .medium))
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            }
        }
        .padding(Space.l)
    }

    private var weeklyGoalCard: some View {
        let calendar = beijingCalendar
        let weekStart = PomodoroHistoryRangePolicy.weekStart(
            containing: Date(),
            calendar: calendar
        )
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart)
            ?? weekStart.addingTimeInterval(7 * 86_400)
        let weekRecords = store.pomodoroHistory.filter { record in
            record.phase == .focus
                && record.actualDuration > 0
                && record.endedAt > weekStart
                && record.startedAt < weekEnd
        }
        let weekSeconds = weekRecords.reduce(0.0) {
            $0 + displayedDuration(for: $1, within: (start: weekStart, end: weekEnd))
        }
        let goalSeconds = max(3600.0, Double(state.weeklyFocusGoalMinutes * 60))
        let progress = min(1.0, weekSeconds / goalSeconds)
        let percent = Int((progress * 100).rounded())
        let achieved = weekSeconds >= goalSeconds
        let goalColor = achieved ? BrandPalette.success : stopwatchColor
        let goalHours = max(1, state.weeklyFocusGoalMinutes / 60)

        return VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    HStack(spacing: Space.s) {
                        Text("本周专注目标")
                            .font(AppType.ui(Typo.body, .medium))
                            .tracking(Tracking.heading)
                        StatusPillBadge(
                            title: achieved ? "已达标" : "进行中 \(percent)%",
                            icon: achieved ? "checkmark.circle.fill" : "target",
                            color: goalColor
                        )
                    }
                    Text("按北京时间周一至周日累计 · 包含番茄钟与正计时")
                        .font(AppType.caption())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(formatHistoryDuration(weekSeconds)) / \(goalHours) 小时")
                    .font(AppType.ui(Typo.footnote, .semibold))
                    .foregroundStyle(goalColor)
                Button {
                    presentedSheet = .weeklyGoal
                } label: {
                    Label("调整", systemImage: "pencil")
                        .font(AppType.caption(12, weight: .medium))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("修改每周专注目标")
                .accessibilityLabel("修改每周专注目标")
                .accessibilityIdentifier("timeslot.pomodoro.weekly-goal.edit")
            }

            TimeSlotProgressBar(
                progress: CGFloat(progress),
                color: goalColor,
                height: 8,
                showsKnob: true,
                showsMilestones: true
            )
        }
        .padding(Space.l)
        .nestedSurface()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "本周专注目标，已完成 \(formatHistoryDuration(weekSeconds))，目标 \(goalHours) 小时，\(achieved ? "已达标" : "完成 \(percent)%")"
        )
    }

    private func focusTrendCard(points: [PomodoroDailyFocusPoint]) -> some View {
        // points 现在是「每天 × 每个任务」一条，日均和最高要先按天合并再算。
        let dayTotals = Dictionary(grouping: points, by: \.day)
            .mapValues { $0.reduce(0.0) { $0 + $1.duration } }
        let total = dayTotals.values.reduce(0, +)
        let average = dayTotals.isEmpty ? 0 : total / Double(dayTotals.count)
        let best = dayTotals.values.max()
        let order = taskOrder(in: points)

        return VStack(alignment: .leading, spacing: Space.l) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("专注趋势")
                        .font(AppType.title(15))
                        .tracking(0.2)
                    Text("每日累计专注时长 · 点击图表查看当天明细")
                        .font(AppType.caption())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: Space.l) {
                    PomodoroChartMetric(label: "累计", value: formatHistoryDuration(total))
                    PomodoroChartMetric(label: "专注日均", value: formatHistoryDuration(average))
                    PomodoroChartMetric(
                        label: "最高",
                        value: best.map { formatHistoryDuration($0) } ?? "-"
                    )
                }
            }

            if points.isEmpty {
                HStack(spacing: Space.m) {
                    Image(systemName: "chart.bar.xaxis")
                        .foregroundStyle(.secondary)
                    Text("所选日期内还没有专注数据")
                        .font(AppType.ui(Typo.footnote))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 118)
                .nestedSurface()
            } else {
                Chart {
                    ForEach(points) { point in
                    // 同一天的多个任务会自动堆叠，每段用该任务的固定配色。
                    BarMark(
                        x: .value("日期", point.day, unit: .day),
                        y: .value("专注分钟", point.duration / 60),
                        width: .ratio(0.65)
                    )
                    .foregroundStyle(by: .value("任务", point.taskTitle))
                    .cornerRadius(3)
                    .accessibilityLabel("\(beijingDateString(point.day, dateStyle: .abbreviated, timeStyle: .omitted)) \(point.taskTitle)")
                    .accessibilityValue(formatHistoryDuration(point.duration))
                    }
                    if let selectedTrendDate {
                        RuleMark(x: .value("选中日期", selectedTrendDate, unit: .day))
                            .foregroundStyle(Color.primary.opacity(0.35))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle().fill(Color.clear).contentShape(Rectangle())
                            .onTapGesture { location in
                                guard let plotFrame = proxy.plotFrame else { return }
                                let frame = geometry[plotFrame]
                                guard frame.contains(location) else { return }
                                selectedTrendDate = proxy.value(atX: location.x - frame.minX)
                            }
                    }
                }
                .chartForegroundStyleScale(
                    domain: order,
                    range: order.map { title in
                        let hex = store.pomodoroTasks.first {
                            PomodoroTaskPalette.normalized($0.title) == title
                        }?.colorHex ?? PomodoroTaskPalette.fallbackColorHex(for: title)
                        return DataSignal.color(hex: hex)
                    }
                )
                .chartLegend(position: .bottom, alignment: .leading, spacing: Space.m)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: min(7, max(2, dayTotals.count)))) {
                        AxisTick()
                            .foregroundStyle(Color.secondary.opacity(0.28))
                        AxisValueLabel(format: .dateTime.month(.defaultDigits).day(.twoDigits))
                            .font(AppType.caption())
                            .foregroundStyle(.secondary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) {
                        AxisGridLine()
                            .foregroundStyle(Surface.gridLine)
                        AxisTick()
                            .foregroundStyle(Color.secondary.opacity(0.28))
                        AxisValueLabel()
                            .font(AppType.caption())
                            .foregroundStyle(.secondary)
                    }
                }
                .chartYAxisLabel("分钟", position: .top, alignment: .leading)
                .frame(height: 172)
                .padding(.top, Space.xs)

                if let selectedTrendDate {
                    let selectedPoints = points.filter { beijingCalendar.isDate($0.day, inSameDayAs: selectedTrendDate) }
                    VStack(alignment: .leading, spacing: Space.s) {
                        HStack {
                            Text(beijingDateString(selectedTrendDate, dateStyle: .abbreviated, timeStyle: .omitted))
                            Spacer()
                            Text(formatHistoryDuration(selectedPoints.reduce(0) { $0 + $1.duration }))
                                .monospacedDigit()
                        }
                        .font(AppType.ui(Typo.footnote, .semibold))
                        ForEach(selectedPoints) { point in
                            HStack {
                                Circle().fill(store.taskColor(for: point.taskTitle)).frame(width: 7, height: 7)
                                Text(point.taskTitle)
                                Spacer()
                                Text(formatHistoryDuration(point.duration)).monospacedDigit()
                            }
                            .font(AppType.caption())
                        }
                        if selectedPoints.isEmpty {
                            Text("当天没有已保存的专注记录").font(AppType.caption()).foregroundStyle(.secondary)
                        }
                    }
                    .padding(Space.m)
                    .nestedSurface()
                }
            }
        }
        .padding(Space.l)
        .nestedSurface()
    }

    private var taskBreakdownCard: some View {
        let items = taskBreakdown
        let totalDuration = items.reduce(0.0) { $0 + $1.duration }

        return VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .firstTextBaseline) {
                Text("按任务分布")
                    .font(AppType.title(15))
                    .tracking(0.2)
                Spacer()
                Text("仅统计专注时长")
                    .font(AppType.caption())
                    .foregroundStyle(.secondary)
            }

            if items.isEmpty {
                Text("所选范围内还没有专注记录")
                    .font(AppType.ui(Typo.footnote))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Space.xs)
            } else {
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        ForEach(items, id: \.title) { item in
                            Rectangle()
                                .fill(store.taskColor(for: item.title))
                                .frame(width: geometry.size.width * item.duration / max(1, totalDuration))
                                .help("\(item.title) · \(formatHistoryDuration(item.duration))")
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .frame(height: 16)
                .accessibilityLabel("各任务占总专注时间的比例，下方列出明细")

                VStack(spacing: Space.s) {
                    ForEach(items, id: \.title) { item in
                        let sharePercent = totalDuration > 0 ? Int((item.duration / totalDuration * 100).rounded()) : 0
                        HStack(spacing: Space.m) {
                            Circle()
                                .fill(store.taskColor(for: item.title))
                                .frame(width: 8, height: 8)
                            Text(item.title)
                                .font(AppType.ui(Typo.footnote))
                                .lineLimit(1)
                                .frame(width: 92, alignment: .leading)
                            TimeSlotProgressBar(
                                progress: CGFloat(min(1, item.duration / max(1, totalDuration))),
                                color: store.taskColor(for: item.title),
                                height: 7,
                                showsKnob: false
                            )
                            HStack(spacing: 4) {
                                Text("\(sharePercent)%")
                                    .font(AppType.caption(11, weight: .medium))
                                    .foregroundStyle(.tertiary)
                                Text(formatHistoryDuration(item.duration))
                                    .font(AppType.caption(Typo.caption, weight: .semibold))
                            }
                            .frame(width: 88, alignment: .trailing)
                        }
                    }
                }
            }
        }
        .padding(Space.l)
        .nestedSurface()
    }

    private var historyFilter: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("记录范围")
                .font(AppType.caption(weight: .medium))
                .foregroundStyle(.secondary)

            HStack(spacing: Space.m) {
                TimeSlotSegmentedControl(
                    options: [.today, .week, .last7Days, .thisMonth].map {
                        SegmentOption(id: $0.id, title: $0.title, value: $0)
                    },
                    selection: Binding(
                        get: { historyRange },
                        set: { chooseRecordRange($0) }
                    ),
                    tint: stopwatchColor
                )

                Menu {
                    Button {
                        chooseRecordRange(.custom)
                    } label: {
                        if historyRange == .custom {
                            Label("自定义", systemImage: "checkmark")
                        } else {
                            Text("自定义")
                        }
                    }
                    Button {
                        chooseRecordRange(.all)
                    } label: {
                        if historyRange == .all {
                            Label("全部", systemImage: "checkmark")
                        } else {
                            Text("全部")
                        }
                    }
                } label: {
                    HStack(spacing: Space.xs) {
                        Text(menuOnlyRangeTitle)
                        Image(systemName: "chevron.down")
                            .font(AppType.caption(11, weight: .semibold))
                    }
                    .font(AppType.ui(Typo.footnote, .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .inkPill()
                .help("自定义 / 全部记录")
                .accessibilityLabel("更多记录范围")
            }

            if historyRange == .week {
                HStack(spacing: Space.m) {
                    Label("选择周", systemImage: "calendar")
                        .font(AppType.ui(Typo.footnote, .medium))
                    Spacer()
                    Picker("选择周", selection: $selectedWeekStart) {
                        ForEach(availableWeekStarts, id: \.self) { weekStart in
                            Text(weekOptionTitle(weekStart)).tag(weekStart)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(minWidth: 220)
                    .accessibilityIdentifier("timeslot.pomodoro.history.week")
                }
            } else if historyRange == .custom {
                HStack(spacing: Space.l) {
                    DatePicker("开始日期", selection: Binding(
                        get: { customHistoryStart },
                        set: { customHistoryStart = $0; recordsFollowAnalysis = false }
                    ), displayedComponents: [.date])
                    DatePicker("结束日期", selection: Binding(
                        get: { customHistoryEnd },
                        set: { customHistoryEnd = $0; recordsFollowAnalysis = false }
                    ), displayedComponents: [.date])
                }
                .font(AppType.ui(Typo.footnote))
            }
        }
        .padding(.vertical, Space.m)
    }

    private func weekOptionTitle(_ weekStart: Date) -> String {
        let calendar = beijingCalendar
        let normalizedStart = PomodoroHistoryRangePolicy.weekStart(
            containing: weekStart,
            calendar: calendar
        )
        let currentWeek = PomodoroHistoryRangePolicy.weekStart(
            containing: Date(),
            calendar: calendar
        )
        let previousWeek = calendar.date(byAdding: .day, value: -7, to: currentWeek)
        let lastDay = calendar.date(byAdding: .day, value: 6, to: normalizedStart)
            ?? normalizedStart.addingTimeInterval(6 * 86_400)
        let dateRange = "\(beijingDateString(normalizedStart, dateStyle: .abbreviated, timeStyle: .omitted)) - \(beijingDateString(lastDay, dateStyle: .abbreviated, timeStyle: .omitted))"

        if normalizedStart == currentWeek {
            return "本周 · \(dateRange)"
        }
        if normalizedStart == previousWeek {
            return "上周 · \(dateRange)"
        }
        return dateRange
    }

    /// 菜单里承载的低频范围：选中时让菜单标题直接显示当前范围，避免“无选中”的疑惑。
    private var menuOnlyRangeTitle: String {
        switch historyRange {
        case .custom: return "自定义"
        case .all: return "全部"
        default: return "更多"
        }
    }

    private var recordsScopeNote: String {
        let range = historyRange.title
        if recordsFollowAnalysis {
            return "和上面的统计同一段（\(historyRangeSummary)）。按开始日分组，可修正任务与时间。"
        }
        return "当前是\(range)，和上面的统计不是同一段。上方总量不受这里影响。"
    }

    private func consumeOpenRequest() {
        guard openRequest == .todayInsights else { return }
        workspace = .insights
        analysisDays = 1
        recordsFollowAnalysis = true
        showingRecordDetails = true
        alignRecordsWithAnalysis()
        openRequest = nil
    }

    private func chooseRecordRange(_ range: PomodoroHistoryRange) {
        recordsFollowAnalysis = false
        historyRange = range
    }

    private func alignRecordsWithAnalysis() {
        let calendar = beijingCalendar
        let today = calendar.startOfDay(for: Date())
        switch analysisDays {
        case 1:
            historyRange = .today
        case 7:
            historyRange = .last7Days
        default:
            customHistoryStart = calendar.date(byAdding: .day, value: -(analysisDays - 1), to: today) ?? today
            customHistoryEnd = today
            historyRange = .custom
        }
        showingAllHistory = false
    }

    private var historyRangeSummary: String {
        guard let bounds = historyBounds else { return "全部历史记录" }
        let calendar = beijingCalendar
        let lastDay = calendar.date(byAdding: .day, value: -1, to: bounds.end) ?? bounds.end
        return "\(beijingDateString(bounds.start, dateStyle: .abbreviated, timeStyle: .omitted)) - \(beijingDateString(lastDay, dateStyle: .abbreviated, timeStyle: .omitted))"
    }

    private func displayedDuration(for record: PomodoroSessionRecord) -> TimeInterval {
        displayedDuration(for: record, within: historyBounds)
    }

    private func displayedDuration(
        for record: PomodoroSessionRecord,
        within bounds: (start: Date, end: Date)?
    ) -> TimeInterval {
        FocusStats.clippedDuration(record, within: bounds)
    }

    private var isTimerActive: Bool {
        timerMode == .stopwatch ? state.isStopwatchActive : state.sessionStartedAt != nil
    }

    private func resetTimer() {
        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7)) {
            if timerMode == .stopwatch {
                store.resetStopwatch()
            } else {
                store.resetPomodoro()
            }
        }
    }

    /// 只改其中一项，其余沿用当前值。
    private func applyRhythm(focus: Int? = nil, shortBreak: Int? = nil, longBreak: Int? = nil, rounds: Int? = nil) {
        store.updatePomodoroSettings(
            focusMinutes: focus ?? state.focusMinutes,
            shortBreakMinutes: shortBreak ?? state.shortBreakMinutes,
            longBreakMinutes: longBreak ?? state.longBreakMinutes,
            roundsBeforeLongBreak: rounds ?? state.roundsBeforeLongBreak,
            weeklyFocusGoalMinutes: state.weeklyFocusGoalMinutes
        )
    }

    private func progress(at date: Date) -> CGFloat {
        let total = max(1, state.duration(for: state.phase))
        return min(1, max(0, 1 - state.remaining(at: date) / total))
    }

    private func timerText(at date: Date) -> String {
        let total = max(0, Int(ceil(state.remaining(at: date))))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    /// 正计时没有终点，用「当前这一分钟」的进度当圆环，让走字有视觉反馈。
    private func stopwatchRingProgress(at date: Date) -> CGFloat {
        let elapsed = max(0, state.stopwatchElapsed(at: date))
        return CGFloat((elapsed.truncatingRemainder(dividingBy: 60)) / 60)
    }

    private func timerMeter(at date: Date) -> some View {
        let isStopwatch = timerMode == .stopwatch
        let ink = isStopwatch ? stopwatchColor : phaseColor
        let isLive = isStopwatch ? state.stopwatchRunning : state.isRunning
        let prog = isStopwatch ? stopwatchRingProgress(at: date) : progress(at: date)

        return TimeSlotGlowMeter(
            progress: prog,
            color: ink,
            phaseTitle: isStopwatch ? "正计时" : state.phase.title,
            phaseIcon: isStopwatch ? "stopwatch.fill" : state.phase.icon,
            timeText: isStopwatch
                ? stopwatchTimeText(state.stopwatchElapsed(at: date))
                : timerText(at: date),
            isRunning: isLive
        )
    }

    private var timerStatusTitle: String {
        if timerMode == .stopwatch {
            return stopwatchStatusTitle
        }
        if state.isRunning { return "正在计时" }
        return state.sessionStartedAt == nil ? "等待开始" : "已暂停"
    }

    private var stopwatchStatusTitle: String {
        if state.stopwatchRunning { return "正在计时" }
        return state.isStopwatchActive ? "已暂停" : "等待开始"
    }

    private func timeText(_ value: TimeInterval) -> String {
        let total = max(0, Int(ceil(value)))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private func stopwatchTimeText(_ elapsed: TimeInterval) -> String {
        let total = max(0, Int(elapsed))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func formatHistoryDuration(_ value: TimeInterval) -> String {
        let total = max(0, Int(value.rounded()))
        if total < 60 { return "\(total) 秒" }
        let minutes = total / 60
        let hours = minutes / 60
        if hours > 0 {
            return minutes % 60 == 0 ? "\(hours) 小时" : "\(hours) 小时 \(minutes % 60) 分"
        }
        return "\(minutes) 分钟"
    }
}

struct PomodoroTimerText: View {
    let state: PomodoroState
    let fontSize: CGFloat
    let color: Color

    // 这里不需要外部按秒喂时间：运行中是 .timer，由系统时钟自己走；
    // 暂停时读数来自 pausedRemaining，本来就不随时间变。
    var body: some View {
        Group {
            if state.isRunning, let endDate = state.endDate, endDate.timeIntervalSinceNow > 0 {
                // Keep the app on the same system-clock timer style as the
                // desktop widget. The old ceil(currentDate) text could trail
                // the widget by a couple of seconds when the app timer tick
                // was delivered late by the run loop.
                Text(endDate, style: .timer)
            } else {
                Text(format(state.remaining(at: Date())))
            }
        }
        .font(AppType.timer(fontSize))
        .tracking(Tracking.timer)
        .monospacedDigit()
        .foregroundStyle(color)
        .lineLimit(1)
        .minimumScaleFactor(0.62)
        .frame(maxWidth: 232)
    }

    private func format(_ remaining: TimeInterval) -> String {
        let total = max(0, Int(ceil(remaining)))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

/// 「当前节奏」的一格。原来是纯展示，现在直接是预设菜单——改时长不用再进设置。
struct PomodoroRhythmCell: View {
    let label: String
    let icon: String
    let color: Color
    let current: Int
    @Environment(\.colorScheme) private var colorScheme
    let suffix: String
    let presets: [Int]
    let onSelect: (Int) -> Void

    var body: some View {
        Menu {
            ForEach(presets, id: \.self) { preset in
                Button {
                    onSelect(preset)
                } label: {
                    if preset == current {
                        Label("\(preset) \(suffix)", systemImage: "checkmark")
                    } else {
                        Text("\(preset) \(suffix)")
                    }
                }
            }
        } label: {
            HStack(spacing: Space.s) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .brightness(colorScheme == .dark ? 0.22 : 0)
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(label)
                        .font(AppType.caption())
                        .foregroundStyle(.secondary)
                    HStack(spacing: 3) {
                        Text("\(current) \(suffix)")
                            .font(AppType.ui(Typo.footnote, .medium))
                        Image(systemName: "chevron.down")
                            .font(AppType.caption(11, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.m)
            .padding(.vertical, 10)
            .nestedSurface()
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("点击选择\(label)时长")
    }
}

struct PomodoroTotalCell: View {
    let label: String
    let value: String
    let color: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(label)
                .font(AppType.caption())
                .foregroundStyle(.secondary)
            Text(value)
                .font(AppType.ui(Typo.headline, .semibold))
                .monospacedDigit()
                .foregroundStyle(colorScheme == .dark ? Color.primary : color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.l)
    }
}

/// 固定最多十二周，避免全部历史范围生成过多视图；零投入日期也保留位置。
private struct PomodoroActivityCalendar: View {
    let points: [PomodoroDailyFocusPoint]
    let rangeStart: Date?
    let rangeEnd: Date?
    let tint: Color
    let formatHistoryDuration: (TimeInterval) -> String
    @State private var selectedDay: Date?

    private var totals: [Date: TimeInterval] {
        Dictionary(grouping: points, by: \.day).mapValues { $0.reduce(0) { $0 + $1.duration } }
    }

    var body: some View {
        let calendar = beijingCalendar
        let today = calendar.startOfDay(for: Date())
        let end = min(today, rangeEnd.map { $0.addingTimeInterval(-1) } ?? today)
        let lastDay = calendar.startOfDay(for: end)
        let lastWeek = PomodoroHistoryRangePolicy.weekStart(containing: lastDay, calendar: calendar)
        let limit = calendar.date(byAdding: .day, value: -77, to: lastWeek) ?? lastWeek
        let start = max(limit, rangeStart ?? points.first?.day ?? limit)
        let firstWeek = PomodoroHistoryRangePolicy.weekStart(containing: start, calendar: calendar)
        let dayCount = max(0, calendar.dateComponents([.day], from: firstWeek, to: lastDay).day ?? 0)
        let weekCount = min(12, dayCount / 7 + 1)
        let values = totals
        let visibleValues = values.filter { $0.key >= start && $0.key <= lastDay }
        let activeDays = visibleValues.values.filter { $0 > 0 }.count

        return VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .firstTextBaseline) {
                Text("每日投入").font(AppType.title(15))
                Spacer()
                Text("\(activeDays) 天有投入 · 最多展示最近 12 周")
                    .font(AppType.caption()).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 6) {
                VStack(spacing: 5) {
                    Text("周").frame(height: 18)
                    ForEach(0..<weekCount, id: \.self) { week in
                        let date = calendar.date(byAdding: .day, value: week * 7, to: firstWeek) ?? firstWeek
                        Text("\(calendar.component(.month, from: date))/\(calendar.component(.day, from: date))").frame(height: 28)
                    }
                }
                .font(AppType.caption(11)).foregroundStyle(.secondary)
                ForEach(0..<7, id: \.self) { weekday in
                    VStack(spacing: 5) {
                        Text(["一", "二", "三", "四", "五", "六", "日"][weekday])
                            .font(AppType.caption(11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                            .frame(height: 18)
                        ForEach(0..<weekCount, id: \.self) { week in
                            let day = calendar.date(byAdding: .day, value: week * 7 + weekday, to: firstWeek) ?? firstWeek
                            let valid = day >= start && day <= lastDay
                            let duration = values[day, default: 0]
                            Button { selectedDay = day } label: {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(valid ? tint.opacity(opacity(for: duration)) : Color.clear)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 4)
                                            .strokeBorder(selectedDay == day ? Color.primary : Color.clear, lineWidth: 1.5)
                                    }
                                    .overlay {
                                        if valid {
                                            Text("\(calendar.component(.day, from: day))")
                                                .font(AppType.caption(11, weight: .medium))
                                                .foregroundStyle(duration >= 14400 ? Color.white : Color.primary)
                                        }
                                    }
                                    .frame(maxWidth: .infinity).frame(height: 28)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(!valid)
                            .accessibilityHidden(!valid)
                            .help("\(beijingDateString(day, dateStyle: .abbreviated, timeStyle: .omitted)) · \(formatHistoryDuration(duration))")
                            .accessibilityLabel("\(beijingDateString(day, dateStyle: .abbreviated, timeStyle: .omitted))，专注 \(formatHistoryDuration(duration))")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            HStack {
                if let day = selectedDay, day >= start && day <= lastDay {
                    Text("\(beijingDateString(day, dateStyle: .abbreviated, timeStyle: .omitted)) · \(formatHistoryDuration(values[day, default: 0]))")
                } else {
                    Text("点击色块查看当天投入")
                }
                Spacer()
                Text("0")
                ForEach([0.0, 1, 2, 4, 8], id: \.self) { hours in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(tint.opacity(opacity(for: hours * 3600)))
                        .frame(width: 10, height: 10)
                        .help(hours == 0 ? "无记录" : (hours == 1 ? "不足 2 小时" : (hours == 8 ? "8 小时及以上" : "\(Int(hours))–\(Int(hours * 2)) 小时")))
                }
                Text("8小时+")
            }
            .font(AppType.caption(11)).foregroundStyle(.secondary)
        }
        .padding(Space.l)
        .nestedSurface()
        .environment(\.timeZone, TimeZone(identifier: "Asia/Shanghai")!)
    }

    private func opacity(for duration: TimeInterval) -> Double {
        switch duration {
        case ...0: return 0.08
        case ..<7200: return 0.28
        case ..<14400: return 0.48
        case ..<28800: return 0.72
        default: return 1
        }
    }
}

/// 统计页页头：workspace 与 historyCard 共用，标题只写一份。
private struct AnalysisWorkspaceHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("学习分析")
                .font(AppType.pageTitle(28))
                .tracking(-0.4)
            Text("让每一天的投入，有迹可循。")
                .font(AppType.ui(Typo.footnote)).foregroundStyle(.secondary)
        }
    }
}

private struct FocusAnalysisWorkspace: View {
    let records: [PomodoroSessionRecord]
    let tint: Color
    let taskColor: (String) -> Color
    @Binding var days: Int
    var showsHeader: Bool = true
    var now: Date = Date()
    @State private var selectedTask = "全部科目"
    @State private var selectedDate: Date?

    private struct Slice {
        let day: Date
        let hour: Int
        let task: String
        let seconds: Double
    }

    private func slices(from start: Date, to end: Date) -> [Slice] {
        FocusStats.slices(in: records, from: start, to: end).map {
            Slice(day: $0.day, hour: $0.hour, task: $0.taskTitle, seconds: $0.duration)
        }
    }

    private func duration(_ seconds: Double) -> String {
        let minutes = max(0, Int(seconds / 60))
        return minutes >= 60 ? "\(minutes / 60) 小时 \(minutes % 60) 分" : "\(minutes) 分钟"
    }

    var body: some View {
        let calendar = beijingCalendar
        let window = FocusStats.trailingDayWindow(days: days, containing: now)
        let end = window.end
        let start = window.start
        let previousStart = calendar.date(byAdding: .day, value: -days, to: start)!
        let all = slices(from: previousStart, to: end)
        let current = all.filter { $0.day >= start }
        let previous = all.filter { $0.day < start }.reduce(0) { $0 + $1.seconds }
        let total = current.reduce(0) { $0 + $1.seconds }
        let daily = Dictionary(grouping: current, by: \.day).mapValues { $0.reduce(0) { $0 + $1.seconds } }
        let dates = (0..<days).map { calendar.date(byAdding: .day, value: $0, to: start)! }
        let tasks = Dictionary(grouping: current, by: \.task).mapValues { $0.reduce(0) { $0 + $1.seconds } }
        let order = tasks.keys.sorted { tasks[$0, default: 0] > tasks[$1, default: 0] }
        let average = current
            .filter { selectedTask == "全部科目" || $0.task == selectedTask }
            .reduce(0) { $0 + $1.seconds } / Double(max(days, 1))
        let points = FocusStats.dailyTaskPoints(in: records, from: start, to: end)

        return VStack(alignment: .leading, spacing: 16) {
            if showsHeader {
                HStack(alignment: .top) {
                    AnalysisWorkspaceHeader()
                    Spacer()
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 20) {
                    analysisPeriodPicker
                    Spacer(minLength: 16)
                    analysisTaskPicker(order: order)
                }
                VStack(alignment: .leading, spacing: 12) {
                    analysisPeriodPicker
                    analysisTaskPicker(order: order)
                }
            }
            Text("总量和科目分配包含全部科目。科目筛选只改变趋势图和时段图。")
                .font(AppType.caption())
                .foregroundStyle(Color.primary.opacity(0.72))

            let sessionCount = records.filter {
                FocusStats.isSavedFocus($0) && $0.endedAt > start && $0.startedAt < end
            }.count
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(days == 1 ? "今天 · 已记录投入" : "近 \(days) 天 · 已记录投入")
                        .font(AppType.caption()).foregroundStyle(Color.primary.opacity(0.72))
                    Text(duration(total)).font(AppType.ui(32, .semibold)).monospacedDigit().minimumScaleFactor(0.7).lineLimit(1)
                    Text(FocusStats.periodComparisonCaption(days: days, previousSeconds: previous))
                        .font(AppType.caption())
                        .foregroundStyle(Color.primary.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
                if days == 1 {
                    metric("记录次数", "\(sessionCount)", "已保存的专注")
                    metric("科目", order.isEmpty ? "0" : "\(order.count)", order.first.map { "最多是 \($0)" } ?? "今天还没有记录")
                } else {
                    metric("日均投入", duration(total / Double(days)), "含零投入日期")
                    metric("学习天数", "\(daily.count) / \(days)", "今天尚未结束")
                }
            }
            .padding(.vertical, 8)

            if days > 1 {
                Divider()
                HStack {
                    Text("投入趋势").font(AppType.title(Typo.headline))
                    Spacer()
                    Text(selectedTask).font(AppType.caption()).foregroundStyle(.secondary)
                }
                let chartPoints = selectedTask == "全部科目"
                    ? points
                    : points.filter { $0.taskTitle == selectedTask }
                StackedFocusChart(
                    points: chartPoints,
                    days: dates,
                    taskColor: taskColor,
                    height: 220,
                    averageHours: average / 3600,
                    selectedDate: selectedDate,
                    onSelectDate: { selectedDate = $0 }
                )
                if let selectedDate {
                    let day = calendar.startOfDay(for: selectedDate)
                    let detail = Dictionary(grouping: current.filter { $0.day == day }, by: \.task).mapValues { $0.reduce(0) { $0 + $1.seconds } }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(beijingDateString(day, dateStyle: .abbreviated, timeStyle: .omitted)) · \(duration(daily[day, default: 0]))").font(AppType.ui(Typo.footnote, .semibold))
                        ForEach(detail.keys.sorted(), id: \.self) { task in
                            HStack { Text(task).foregroundStyle(taskColor(task)); Spacer(); Text(duration(detail[task, default: 0])) }.font(AppType.caption())
                        }
                    }.padding(12).nestedSurface()
                } else {
                    Text("点击柱形查看当天科目明细 · 虚线为所选科目的日均投入")
                        .font(AppType.caption()).foregroundStyle(.secondary)
                }
            }

            Divider()
            Text(days == 1 ? "今天的科目" : "科目分配").font(AppType.title(Typo.headline))
            if order.isEmpty { Text(days == 1 ? "今天还没有已保存的学习记录。" : "完成并保存一次学习后，这里会显示科目分配。").foregroundStyle(.secondary) }
            ForEach(order, id: \.self) { task in
                let taskDays = Dictionary(grouping: current.filter { $0.task == task }, by: \.day).mapValues { $0.reduce(0) { $0 + $1.seconds } }
                let share = tasks[task, default: 0] / max(1, total)
                HStack(spacing: 16) {
                    Circle().fill(taskColor(task)).frame(width: 8, height: 8)
                    Text(task).font(AppType.ui(Typo.footnote, .medium)).frame(width: 72, alignment: .leading).lineLimit(1)
                    if days == 1 {
                        GeometryReader { proxy in
                            Capsule()
                                .fill(taskColor(task).opacity(0.16))
                                .overlay(alignment: .leading) {
                                    Capsule()
                                        .fill(taskColor(task))
                                        .frame(width: max(4, proxy.size.width * share))
                                }
                        }
                        .frame(height: 8)
                        .accessibilityLabel("\(task)占今天 \(Int((share * 100).rounded()))%")
                    } else {
                        Chart(dates, id: \.self) { date in
                            BarMark(x: .value("日期", date, unit: .day), y: .value("小时", taskDays[date, default: 0] / 3600)).foregroundStyle(taskColor(task))
                        }
                        .chartXAxis(.hidden)
                        .chartYAxis(.hidden)
                        .chartYScale(domain: 0...max(0.25, (daily.values.max() ?? 0) / 3600))
                        .frame(height: 34)
                        .accessibilityLabel("\(task)近\(days)天的每日投入")
                    }
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(duration(tasks[task, default: 0])).font(AppType.ui(Typo.footnote, .semibold))
                        Text(String(format: "%.0f%%", share * 100)).font(AppType.caption()).foregroundStyle(.secondary)
                    }.frame(width: 105, alignment: .trailing).monospacedDigit()
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text(hourChartTitle).font(AppType.title(Typo.headline))
                Text(hourChartNote)
                    .font(AppType.caption()).foregroundStyle(Color.primary.opacity(0.72))
            }
            let hourWindow = hourChartWindow(calendar: calendar, periodStart: start, periodEnd: end)
                let dayHourly = FocusStats.hourlySeconds(
                    in: records,
                    from: hourWindow.start,
                    to: hourWindow.end,
                    selectedTask: selectedTask
                )
                Text(selectedTask == "全部科目" ? "时段图包含全部科目。" : "时段图只含「\(selectedTask)」，上面的总量仍是全部科目。")
                    .font(AppType.caption())
                    .foregroundStyle(Color.primary.opacity(0.72))
                Chart(0..<24, id: \.self) { hour in
                    BarMark(x: .value("时刻", hour), y: .value("累计小时", dayHourly[hour, default: 0] / 3600))
                        .foregroundStyle(tint.opacity(0.75)).cornerRadius(2)
                        .accessibilityLabel("\(hour)点，\(duration(dayHourly[hour, default: 0]))")
                }
                .chartXAxis { AxisMarks(values: [0, 6, 12, 18, 23]) { value in AxisValueLabel { if let hour = value.as(Int.self) { Text("\(hour)时") } } } }
                .chartYAxisLabel("小时").frame(height: 110)

            if days > 7 {
                PomodoroActivityCalendar(points: points.sorted { $0.day < $1.day }, rangeStart: start, rangeEnd: end, tint: tint, formatHistoryDuration: duration)
            }
            Text("仅统计已保存的专注与正计时记录；进行中的计时将在停止并记录后计入。日期按北京时间划分，周期含今天。")
                .font(AppType.caption()).foregroundStyle(.secondary)
        }
        .onChange(of: days) { selectedDate = nil; selectedTask = "全部科目" }
        .onChange(of: order.joined(separator: "\u{1f}")) { _, names in
            let titles = names.split(separator: "\u{1f}").map(String.init)
            if selectedTask != "全部科目", !titles.contains(selectedTask) {
                selectedTask = "全部科目"
            }
            if let selectedDate, days > 1, !dates.contains(where: { calendar.isDate($0, inSameDayAs: selectedDate) }) {
                self.selectedDate = nil
            }
        }
        .environment(\.timeZone, TimeZone(identifier: "Asia/Shanghai")!)
    }

    private var hourChartTitle: String {
        if days <= 1 { return "今天的时段" }
        if selectedDate != nil { return "当天时段" }
        return "本周期的时段"
    }

    private var hourChartNote: String {
        if days > 1, selectedDate == nil {
            return "未点选日期时，按整个周期的小时累计。点选某一天后只看当天。"
        }
        if days <= 1 {
            return "按北京时间的小时累计。"
        }
        return "按所选日期的小时累计。"
    }

    private func hourChartWindow(calendar: Calendar, periodStart: Date, periodEnd: Date) -> (start: Date, end: Date) {
        if days > 1, let selectedDate {
            let day = calendar.startOfDay(for: selectedDate)
            let end = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
            return (day, end)
        }
        return (periodStart, periodEnd)
    }

    private var analysisPeriodPicker: some View {
        HStack(spacing: 12) {
            Text("分析周期").font(AppType.ui(Typo.footnote, .medium))
            // 用应用自己的分段控件，选中态是墨色纸面，不引入系统蓝。
            TimeSlotSegmentedControl(
                options: [(1, "今天"), (7, "7 天"), (30, "30 天"), (90, "90 天")].map {
                    SegmentOption(id: "analysis.\($0.0)", title: $0.1, value: $0.0)
                },
                selection: $days,
                tint: tint
            )
            .frame(width: 280)
        }
    }

    private func analysisTaskPicker(order: [String]) -> some View {
        Picker("图表科目", selection: $selectedTask) {
            Text("全部科目").tag("全部科目")
            ForEach(order, id: \.self) { Text($0).tag($0) }
        }.frame(width: 220)
    }

    private func metric(_ title: String, _ value: String, _ note: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(AppType.caption()).foregroundStyle(.secondary)
            Text(value).font(AppType.ui(20, .semibold)).monospacedDigit()
            Text(note).font(AppType.caption(11)).foregroundStyle(.secondary)
        }
    }
}

struct PomodoroChartMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .trailing, spacing: Space.xs) {
            Text(label)
                .font(AppType.caption())
                .foregroundStyle(.secondary)
            Text(value)
                .font(AppType.ui(Typo.body, .semibold))
                .foregroundStyle(.primary)
        }
    }
}

struct PomodoroHistoryRow: View {
    let record: PomodoroSessionRecord
    let displayedDuration: TimeInterval?
    let taskColor: Color
    @Environment(\.colorScheme) private var colorScheme

    init(record: PomodoroSessionRecord, displayedDuration: TimeInterval? = nil, taskColor: Color) {
        self.record = record
        self.displayedDuration = displayedDuration
        self.taskColor = taskColor
    }

    private var color: Color {
        DataSignal.color(hex: record.phase.colorHex)
    }

    var body: some View {
        HStack(spacing: Space.m) {
            Image(systemName: record.phase.icon)
                .font(AppType.ui(Typo.body, .medium))
                .foregroundStyle(color)
                .brightness(colorScheme == .dark ? 0.22 : 0)
                .frame(width: 28, height: 28)
                .background(color.opacity(colorScheme == .dark ? 0.22 : 0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(spacing: Space.s) {
                    Text(record.phase.title)
                        .font(AppType.ui(Typo.footnote, .medium))
                    Text(record.status.title)
                        .font(AppType.caption(weight: .medium))
                        .foregroundStyle(record.status == .completed ? color : .secondary)
                }
                HStack(spacing: Space.xs) {
                    Circle()
                        .fill(taskColor)
                        .frame(width: 6, height: 6)
                    Text(PomodoroTaskPalette.normalized(record.taskTitle))
                        .font(AppType.caption())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: Space.xs) {
                Text(durationText(record.actualDuration))
                    .font(AppType.ui(Typo.footnote, .semibold))
                    .monospacedDigit()
                Text(beijingDateString(record.startedAt, dateStyle: .abbreviated, timeStyle: .shortened))
                    .font(AppType.caption())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, Space.s)
    }

    private func durationText(_ value: TimeInterval) -> String {
        let total = max(0, Int((displayedDuration ?? value).rounded()))
        if record.status == .stopwatch {
            if total < 60 { return "\(total) 秒" }
            let minutes = total / 60
            let seconds = total % 60
            return seconds == 0 ? "\(minutes) 分钟" : "\(minutes) 分 \(seconds) 秒"
        }
        let plannedMinutes = max(1, Int(record.plannedDuration / 60))
        if total < 60 { return "\(total) 秒 / \(plannedMinutes) 分" }
        return "\(total / 60) 分 \(total % 60) 秒 / \(plannedMinutes) 分"
    }
}

struct PomodoroTasksView: View {
    let tasks: [PomodoroTask]
    let selectedTitle: String
    let canSwitch: Bool
    let onSelect: (UUID) -> Void
    let onAdd: (String) -> Void
    let onDelete: (PomodoroTask) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var newTaskTitle = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            HStack {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("番茄任务")
                        .font(AppType.title(Typo.sheetTitle))
                        .tracking(Tracking.heading)
                    Text("为不同学习内容保存任务，开始前选择本轮任务")
                        .font(AppType.ui(Typo.footnote))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            HStack(spacing: Space.m) {
                TextField("输入新任务名称", text: $newTaskTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addTask)
                Button(action: addTask) {
                    Label("添加", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                        taskRow(task)
                        if index < tasks.count - 1 {
                            Divider().padding(.leading, 42)
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: 300)
            .cardSurface()

            if !canSwitch {
                Label(
                    "当前阶段已经开始。请先停止并记录，之后再切换任务。",
                    systemImage: "lock.fill"
                )
                .font(AppType.caption())
                .foregroundStyle(.secondary)
            }
        }
        .padding(Space.xl)
        .frame(width: 500, height: max(320, min(540, CGFloat(tasks.count * 50 + 210))))
    }

    private func taskRow(_ task: PomodoroTask) -> some View {
        let isSelected = task.title == selectedTitle
        // 这里的颜色和统计里是同一套，方便对照图表上的分段是哪个任务。
        let taskColor = DataSignal.color(
            hex: task.colorHex.isEmpty
                ? PomodoroTaskPalette.fallbackColorHex(for: task.title)
                : task.colorHex
        )
        return HStack(spacing: Space.m) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? taskColor : .secondary)
                .frame(width: 22)

            Button {
                onSelect(task.id)
            } label: {
                HStack(spacing: Space.s) {
                    Circle()
                        .fill(taskColor)
                        .frame(width: 8, height: 8)
                    Text(task.title)
                        .font(AppType.ui(Typo.body, isSelected ? .semibold : .regular))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(TimeSlotPressableStyle())
            .disabled(!canSwitch || isSelected)

            if isSelected {
                Text("当前")
                    .font(AppType.caption(weight: .medium))
                    .foregroundStyle(taskColor)
                    .padding(.horizontal, Space.s)
                    .padding(.vertical, Space.xs)
                    .background(taskColor.opacity(0.1))
                    .clipShape(Capsule())
            }

            Button(role: .destructive) {
                onDelete(task)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .disabled(tasks.count <= 1 || (isSelected && !canSwitch))
            .accessibilityLabel("删除任务：\(task.title)")
            .help(tasks.count <= 1 ? "至少保留一个任务" : "删除任务")
        }
        .padding(.horizontal, Space.l)
        .frame(height: 50)
    }

    private func addTask() {
        let title = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        onAdd(title)
        newTaskTitle = ""
    }
}

struct PomodoroSettingsView: View {
    let accent: Color
    let breakAccent: Color
    let longBreakAccent: Color
    let onSave: (Int, Int, Int, Int, Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var focusMinutes: Int
    @State private var shortBreakMinutes: Int
    @State private var longBreakMinutes: Int
    @State private var roundsBeforeLongBreak: Int
    @State private var weeklyGoalHours: Int

    init(state: PomodoroState, accent: Color, breakAccent: Color, longBreakAccent: Color, onSave: @escaping (Int, Int, Int, Int, Int) -> Void) {
        self.accent = accent
        self.breakAccent = breakAccent
        self.longBreakAccent = longBreakAccent
        self.onSave = onSave
        _focusMinutes = State(initialValue: state.focusMinutes)
        _shortBreakMinutes = State(initialValue: state.shortBreakMinutes)
        _longBreakMinutes = State(initialValue: state.longBreakMinutes)
        _roundsBeforeLongBreak = State(initialValue: state.roundsBeforeLongBreak)
        _weeklyGoalHours = State(initialValue: max(1, Int((Double(state.weeklyFocusGoalMinutes) / 60).rounded())))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            HStack {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("番茄钟设置")
                        .font(AppType.title(Typo.sheetTitle))
                        .tracking(Tracking.heading)
                    Text("调整适合你的专注与休息节奏")
                        .font(AppType.ui(Typo.footnote))
                        .lineSpacing(2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            VStack(spacing: 0) {
                settingRow(
                    title: "专注时长", value: $focusMinutes, range: 1...120, suffix: "分钟",
                    presets: PomodoroPresets.focus,
                    accent: accent
                )
                Divider()
                settingRow(
                    title: "短休息", value: $shortBreakMinutes, range: 1...30, suffix: "分钟",
                    presets: PomodoroPresets.shortBreak,
                    accent: breakAccent
                )
                Divider()
                settingRow(
                    title: "长休息", value: $longBreakMinutes, range: 1...60, suffix: "分钟",
                    presets: PomodoroPresets.longBreak,
                    accent: longBreakAccent
                )
                Divider()
                settingRow(
                    title: "长休息间隔", value: $roundsBeforeLongBreak, range: 2...8, suffix: "轮",
                    presets: PomodoroPresets.rounds,
                    accent: .secondary
                )
                Divider()
                settingRow(
                    title: "每周专注目标", value: $weeklyGoalHours, range: 1...168, suffix: "小时",
                    presets: [5, 7, 10, 14, 20, 30],
                    accent: accent
                )
            }
            .padding(.horizontal, Space.l)
            .cardSurface()

            Text("按北京时间周一至周日统计，正计时和已完成的专注阶段都会计入小组件。")
                .font(AppType.caption())
                .foregroundStyle(.secondary)
                .lineSpacing(2)

            HStack {
                Spacer()
                Button("保存") {
                    onSave(
                        focusMinutes,
                        shortBreakMinutes,
                        longBreakMinutes,
                        roundsBeforeLongBreak,
                        weeklyGoalHours
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.xl)
        .frame(width: 430)
    }

    private func settingRow(
        title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        suffix: String,
        presets: [Int],
        accent: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                Text(title)
                    .font(AppType.ui(Typo.body, .medium))
                Spacer()
                Stepper(value: value, in: range) {
                    Text("\(value.wrappedValue) \(suffix)")
                        .font(AppType.ui(Typo.body, .semibold))
                        .monospacedDigit()
                        .frame(width: 72, alignment: .trailing)
                }
            }
            // Stepper 保留给微调，常用值直接一键选。
            HStack(spacing: Space.s) {
                ForEach(presets, id: \.self) { preset in
                    PomodoroPresetChip(
                        value: preset,
                        isSelected: value.wrappedValue == preset,
                        accent: accent
                    ) {
                        value.wrappedValue = preset
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, Space.m)
    }
}

/// 只调整「每周专注目标」的弹窗：从周目标读数直接进入，
/// 不用先打开整页番茄钟设置再找到最后一行。
struct WeeklyGoalSettingsView: View {
    let accent: Color
    let onSave: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var goalHours: Int

    init(goalHours: Int, accent: Color, onSave: @escaping (Int) -> Void) {
        self.accent = accent
        self.onSave = onSave
        _goalHours = State(initialValue: max(1, goalHours))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            HStack {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("每周专注目标")
                        .font(AppType.title(Typo.sheetTitle))
                        .tracking(Tracking.heading)
                    Text("按北京时间周一至周日累计，番茄钟与正计时都会计入")
                        .font(AppType.ui(Typo.footnote))
                        .lineSpacing(2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            VStack(alignment: .leading, spacing: Space.s) {
                HStack {
                    Text("目标时长")
                        .font(AppType.ui(Typo.body, .medium))
                    Spacer()
                    Stepper(value: $goalHours, in: 1...168) {
                        Text("\(goalHours) 小时")
                            .font(AppType.ui(Typo.body, .semibold))
                            .monospacedDigit()
                            .frame(width: 72, alignment: .trailing)
                    }
                }
                // Stepper 保留给微调，常用值直接一键选。
                HStack(spacing: Space.s) {
                    ForEach([5, 7, 10, 14, 20, 30], id: \.self) { preset in
                        PomodoroPresetChip(
                            value: preset,
                            isSelected: goalHours == preset,
                            accent: accent
                        ) {
                            goalHours = preset
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.s)
            .cardSurface()

            Text("目标只影响周进度和达标状态，不会改动已记录的专注时长。")
                .font(AppType.caption())
                .foregroundStyle(.secondary)
                .lineSpacing(2)

            HStack {
                Spacer()
                Button("保存") {
                    onSave(goalHours)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("timeslot.weekly-goal.save")
            }
        }
        .padding(Space.xl)
        .frame(width: 430)
    }
}

struct PomodoroPresetChip: View {
    let value: Int
    let isSelected: Bool
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("\(value)")
                .font(AppType.ui(Typo.footnote, isSelected ? .bold : .medium))
                .frame(minWidth: 24)
                .padding(.vertical, Space.xs)
                .padding(.horizontal, Space.s)
                .background(isSelected ? accent.opacity(0.16) : Surface.nested)
                .foregroundStyle(isSelected ? accent : Color.primary.opacity(0.75))
                .clipShape(Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(TimeSlotPressableStyle())
    }
}

/// 修正历史记录弹窗：调整起止时间与任务名，时长按新墙钟重算。
struct PomodoroHistoryEditSheet: View {
    let record: PomodoroSessionRecord
    let tasks: [PomodoroTask]
    let phaseTitle: String
    let onSave: (Date, Date, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var startedAt: Date
    @State private var endedAt: Date
    @State private var taskTitle: String

    init(
        record: PomodoroSessionRecord,
        tasks: [PomodoroTask],
        phaseTitle: String,
        onSave: @escaping (Date, Date, String) -> Void
    ) {
        self.record = record
        self.tasks = tasks
        self.phaseTitle = phaseTitle
        self.onSave = onSave
        _startedAt = State(initialValue: record.startedAt)
        _endedAt = State(initialValue: record.endedAt)
        _taskTitle = State(initialValue: PomodoroTaskPalette.normalized(record.taskTitle))
    }

    private var edited: PomodoroHistoryEditMath.Preview? {
        PomodoroHistoryEditMath.preview(previous: record, startedAt: startedAt, endedAt: endedAt)
    }

    private func clockText(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total < 60 { return "\(total) 秒" }
        let minutes = total / 60
        let hours = minutes / 60
        if hours > 0 {
            return minutes % 60 == 0 ? "\(hours) 小时" : "\(hours) 小时 \(minutes % 60) 分"
        }
        let remain = total % 60
        return remain == 0 ? "\(minutes) 分钟" : "\(minutes) 分 \(remain) 秒"
    }

    private var canSave: Bool {
        edited != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            HStack(spacing: Space.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("修正记录")
                        .font(AppType.title(Typo.sheetTitle))
                        .tracking(Tracking.heading)
                    Text("\(phaseTitle) · 调整起止时间与任务名，修正漏关计时产生的误差")
                        .font(AppType.caption())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
            }

            VStack(alignment: .leading, spacing: Space.m) {
                HStack {
                    Text("任务")
                        .font(AppType.ui(Typo.footnote, .medium))
                    Spacer()
                    Picker("任务", selection: $taskTitle) {
                        ForEach(tasks, id: \.title) { task in
                            Text(task.title).tag(PomodoroTaskPalette.normalized(task.title))
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 200)
                }

                Divider()

                HStack {
                    Text("开始时间")
                        .font(AppType.ui(Typo.footnote, .medium))
                    Spacer()
                    DatePicker(
                        "开始时间",
                        selection: $startedAt,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                    .datePickerStyle(.field)
                }

                Divider()

                HStack {
                    Text("结束时间")
                        .font(AppType.ui(Typo.footnote, .medium))
                    Spacer()
                    DatePicker(
                        "结束时间",
                        selection: $endedAt,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                    .datePickerStyle(.field)
                }

                Divider()

                HStack {
                    Text("起止跨度")
                        .font(AppType.ui(Typo.footnote, .medium))
                    Spacer()
                    Text(edited.map { clockText($0.wall) } ?? "—")
                        .font(AppType.ui(Typo.footnote, .medium))
                        .monospacedDigit()
                        .foregroundStyle(Color.primary.opacity(0.72))
                }
                HStack {
                    Text("计入时长")
                        .font(AppType.ui(Typo.footnote, .medium))
                    Spacer()
                    Text(edited.map { clockText($0.actual) } ?? "—")
                        .font(AppType.ui(Typo.body, .semibold))
                        .monospacedDigit()
                        .foregroundStyle(canSave ? Color.primary : Color.orange)
                }
                Text(edited?.timesUnchanged == true
                     ? "只改科目不会改变计入时长。起止跨度是墙上的时间，计入时长才是会保存的实际用时。"
                     : "已改起止时间。含暂停的记录按原来的实际用时比例折算，预览和保存用同一结果。")
                    .font(AppType.caption())
                    .foregroundStyle(Color.primary.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)

                if !canSave {
                    Label("结束时间需要晚于开始时间", systemImage: "exclamationmark.triangle.fill")
                        .font(AppType.caption(weight: .medium))
                        .foregroundStyle(.orange)
                }
            }
            .padding(Space.l)
            .cardSurface()

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("保存修正") {
                    onSave(startedAt, endedAt, taskTitle)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(Space.xl)
        .frame(width: 480)
    }
}
