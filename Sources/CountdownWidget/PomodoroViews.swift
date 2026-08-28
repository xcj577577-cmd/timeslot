import AppKit
import Charts
import Combine
import SwiftUI

struct PomodoroView: View {
    private enum PresentedSheet: String, Identifiable {
        case tasks
        case settings

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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    init(store: CountdownStore, onSyncWidget: @escaping () -> Void) {
        self.store = store
        self.onSyncWidget = onSyncWidget
        _historyRange = State(initialValue: PomodoroHistoryRange(rawValue: countdownDefaults.string(forKey: "pomodoroHistoryRange") ?? "") ?? .all)
        _customHistoryStart = State(
            initialValue: beijingCalendar.date(byAdding: .day, value: -6, to: Date()) ?? Date()
        )
        _customHistoryEnd = State(initialValue: Date())
        _selectedWeekStart = State(
            initialValue: PomodoroHistoryRangePolicy.weekStart(containing: Date())
        )
        // 正计时进行中时，重启应用也要回到正计时页面，避免计时器在后台偷偷走。
        let storedMode = countdownDefaults
            .string(forKey: "pomodoroTimerMode")
            .flatMap(PomodoroTimerMode.init(rawValue:))
        if store.pomodoro.isStopwatchActive {
            _timerMode = State(initialValue: .stopwatch)
        } else {
            _timerMode = State(initialValue: storedMode ?? .countdown)
        }
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

    // 这些范围都是「天」的粒度，跟着渲染时刻取一次就够，不需要每秒重算。
    private var historyBounds: (start: Date, end: Date)? {
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

    private struct DayTaskKey: Hashable {
        let day: Date
        let taskTitle: String
    }

    private var dailyFocusPoints: [PomodoroDailyFocusPoint] {
        let calendar = beijingCalendar
        var totals: [DayTaskKey: TimeInterval] = [:]

        for record in store.pomodoroHistory where record.phase == .focus && record.actualDuration > 0 {
            let taskTitle = PomodoroTaskPalette.normalized(record.taskTitle)
            let wallDuration = record.endedAt.timeIntervalSince(record.startedAt)

            if wallDuration <= 0 {
                let day = calendar.startOfDay(for: record.endedAt)
                let isInSelectedRange = historyBounds.map {
                    record.endedAt >= $0.start && record.endedAt < $0.end
                } ?? true
                if isInSelectedRange {
                    totals[DayTaskKey(day: day, taskTitle: taskTitle), default: 0] += record.actualDuration
                }
                continue
            }

            var rangeStart = record.startedAt
            var rangeEnd = record.endedAt
            if let bounds = historyBounds {
                rangeStart = max(rangeStart, bounds.start)
                rangeEnd = min(rangeEnd, bounds.end)
            }
            guard rangeEnd > rangeStart else { continue }

            var cursor = rangeStart
            while cursor < rangeEnd {
                let day = calendar.startOfDay(for: cursor)
                let nextDay = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86400)
                let segmentEnd = min(rangeEnd, nextDay)
                let segmentRatio = segmentEnd.timeIntervalSince(cursor) / wallDuration
                totals[DayTaskKey(day: day, taskTitle: taskTitle), default: 0] += record.actualDuration * segmentRatio
                cursor = segmentEnd
            }
        }

        return totals
            .map { PomodoroDailyFocusPoint(day: $0.key.day, taskTitle: $0.key.taskTitle, duration: $0.value) }
            .sorted { lhs, rhs in
                lhs.day == rhs.day ? lhs.taskTitle < rhs.taskTitle : lhs.day < rhs.day
            }
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
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("番茄钟")
                        .font(AppType.caption())
                        .foregroundStyle(.secondary)
                    Text(state.taskTitle.isEmpty ? "专注当前任务" : state.taskTitle)
                        .font(AppType.pageTitle(28))
                        .tracking(-0.4)
                        .lineLimit(1)
                }
                Spacer()
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
                        .font(AppType.ui(12.5, .medium))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .foregroundStyle(.primary.opacity(0.78))
                }
                .buttonStyle(TimeSlotPressableStyle())
                .inkPill()
                .accessibilityIdentifier("timeslot.pomodoro.tasks")

                Button(action: onSyncWidget) {
                    Label("设为小组件内容", systemImage: "rectangle.3.group")
                        .font(AppType.ui(12.5, .medium))
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
            .padding(.horizontal, Space.xxl)
            .padding(.bottom, Space.l)

            workspaceContent
        }
        .background(
            LinearGradient(
                colors: [Color.primary.opacity(0.04), Color.clear],
                startPoint: .topLeading,
                endPoint: .center
            )
        )
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
            countdownDefaults.set(historyRange.rawValue, forKey: "pomodoroHistoryRange")
        }
        .onChange(of: selectedWeekStart) {
            showingAllHistory = false
        }
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
                    .padding(.horizontal, Space.xxl)
                    .padding(.bottom, Space.xxl)
            }
            .scrollIndicators(.hidden)
            .accessibilityIdentifier("timeslot.pomodoro.focus-workspace")
        case .insights:
            ScrollView {
                historyCard
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
        .cardSurface(
            cornerRadius: Radius.board,
            borderOpacity: 0.08,
            shadowRadius: 16,
            shadowY: 5
        )
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
        let records = store.pomodoroHistory.filter { record in
            record.status == .stopwatch && beijingCalendar.isDateInToday(record.startedAt)
        }
        let total = records.reduce(0.0) { $0 + $1.actualDuration }
        if records.isEmpty { return "尚无记录" }
        return "\(records.count) 次 · \(formatHistoryDuration(total))"
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

            if timerMode == .countdown && !state.isRunning {
                quickPresetPills
            }

            TimelineView(.periodic(from: .now, by: 1)) { context in
                    let isStopwatch = timerMode == .stopwatch
                    let ink = isStopwatch ? stopwatchColor : phaseColor
                    let isLive = isStopwatch ? state.stopwatchRunning : state.isRunning
                    let prog = isStopwatch
                        ? stopwatchRingProgress(at: context.date)
                        : progress(at: context.date)

                    TimeSlotGlowMeter(
                        progress: prog,
                        color: ink,
                        phaseTitle: isStopwatch ? "正计时" : state.phase.title,
                        phaseIcon: isStopwatch ? "stopwatch.fill" : state.phase.icon,
                        timeText: isStopwatch
                            ? stopwatchTimeText(state.stopwatchElapsed(at: context.date))
                            : timerText(at: context.date),
                        isRunning: isLive
                    )
                }
            .padding(.vertical, Space.m)
            .overlay {
                ConfettiEffectView(isActive: state.phase == .focus && state.remaining(at: Date()) <= 0)
            }
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
                        .font(AppType.ui(13, .medium))
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
                    .font(AppType.ui(13, .medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .foregroundStyle(.primary.opacity(0.82))
                }
                .buttonStyle(TimeSlotPressableStyle())
                .inkPill()
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
                    Label("停止", systemImage: "stop.fill")
                        .font(AppType.ui(13, .medium))
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
                .help("结束当前计时，并把实际用时加入阶段记录")

                if timerMode == .countdown {
                    Button {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7)) {
                            store.skipPomodoroPhase()
                        }
                    } label: {
                        Label("跳过", systemImage: "forward.end.fill")
                            .font(AppType.ui(13, .medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .foregroundStyle(.primary.opacity(0.72))
                    }
                    .buttonStyle(TimeSlotPressableStyle())
                    .inkPill()
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 520)
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.xl)
    }

    private var quickPresetPills: some View {
        HStack(spacing: 6) {
            ForEach([25, 45, 60, 90], id: \.self) { mins in
                let isCurrent = state.focusMinutes == mins
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        store.updatePomodoroSettings(
                            focusMinutes: mins,
                            shortBreakMinutes: state.shortBreakMinutes,
                            longBreakMinutes: state.longBreakMinutes,
                            roundsBeforeLongBreak: state.roundsBeforeLongBreak,
                            weeklyFocusGoalMinutes: state.weeklyFocusGoalMinutes
                        )
                    }
                } label: {
                    Text("\(mins)分")
                        .font(AppType.caption(11.5, weight: isCurrent ? .semibold : .regular))
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
        let records = filteredHistoryRecords
        let visibleRecords = showingAllHistory ? records : Array(records.prefix(8))
        let focusTotal = records.filter { $0.phase == .focus }.reduce(0.0) { $0 + displayedDuration(for: $1) }
        let shortBreakTotal = records.filter { $0.phase == .shortBreak }.reduce(0.0) { $0 + displayedDuration(for: $1) }
        let longBreakTotal = records.filter { $0.phase == .longBreak }.reduce(0.0) { $0 + displayedDuration(for: $1) }

        return VStack(alignment: .leading, spacing: Space.l) {
            HStack {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("阶段记录")
                        .font(AppType.pageTitle(15))
                        .tracking(0.2)
                    Text("按日期范围查看每个阶段的实际用时")
                        .font(AppType.ui(Typo.footnote))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !records.isEmpty {
                    Button("清空全部") {
                        showingClearHistoryConfirmation = true
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
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

            weeklyGoalCard

            focusTrendCard

            taskBreakdownCard

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
                VStack(spacing: 0) {
                    ForEach(Array(visibleRecords.enumerated()), id: \.element.id) { index, record in
                        PomodoroHistoryRow(
                            record: record,
                            displayedDuration: displayedDuration(for: record),
                            taskColor: store.taskColor(for: record.taskTitle)
                        )
                        .contextMenu {
                            Button("修正记录…", systemImage: "slider.horizontal.3") {
                                editingRecord = record
                            }
                            Button("删除这条记录", role: .destructive) {
                                store.deletePomodoroHistory(ids: [record.id], title: record.taskTitle)
                            }
                        }
                        if index < visibleRecords.count - 1 {
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
        .padding(Space.l)
        .cardSurface()
    }

    private var weeklyGoalCard: some View {
        let calendar = beijingCalendar
        let now = Date()
        let currentWeekStart = PomodoroHistoryRangePolicy.weekStart(
            containing: now,
            calendar: calendar
        )
        let currentWeekEnd = calendar.date(byAdding: .day, value: 7, to: currentWeekStart)
            ?? currentWeekStart.addingTimeInterval(7 * 86_400)
        let selectedBounds = historyRange == .week ? historyBounds : nil
        let goalBounds = selectedBounds ?? (start: currentWeekStart, end: currentWeekEnd)
        let isCurrentWeek = goalBounds.start == currentWeekStart
        let weekRecords = store.pomodoroHistory.filter { record in
            record.phase == .focus
                && record.actualDuration > 0
                && record.endedAt > goalBounds.start
                && record.startedAt < goalBounds.end
        }
        let weekSeconds = weekRecords.reduce(0.0) {
            $0 + displayedDuration(for: $1, within: goalBounds)
        }
        let goalSeconds = max(3600.0, Double(state.weeklyFocusGoalMinutes * 60))
        let progress = min(1.0, weekSeconds / goalSeconds)
        let percent = Int((progress * 100).rounded())
        let achieved = weekSeconds >= goalSeconds

        return VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    HStack(spacing: Space.s) {
                        Text(isCurrentWeek ? "本周专注目标" : "所选周专注目标")
                            .font(AppType.ui(Typo.body, .medium))
                            .tracking(Tracking.heading)
                        StatusPillBadge(
                            title: achieved ? "已达标" : "进行中 \(percent)%",
                            icon: achieved ? "checkmark.circle.fill" : "target",
                            color: achieved ? Color.green : stopwatchColor
                        )
                    }
                    Text(
                        isCurrentWeek
                            ? "按北京时间周一至周日累计 · 包含番茄钟与正计时"
                            : "\(historyRangeSummary) · 包含番茄钟与正计时"
                    )
                        .font(AppType.caption())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(formatHistoryDuration(weekSeconds)) / \(max(1, state.weeklyFocusGoalMinutes / 60)) 小时")
                    .font(AppType.ui(Typo.footnote, .semibold))
                    .foregroundStyle(achieved ? Color.green : stopwatchColor)
            }

            TimeSlotProgressBar(
                progress: CGFloat(progress),
                color: achieved ? Color.green : stopwatchColor,
                height: 8,
                showsKnob: true,
                showsMilestones: true
            )
        }
        .padding(Space.l)
        .nestedSurface()
    }

    private var focusTrendCard: some View {
        let points = dailyFocusPoints
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
                        .font(AppType.pageTitle(15))
                        .tracking(0.2)
                    Text("每日累计专注时长 · 按任务分色")
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
                Chart(points) { point in
                    // 同一天的多个任务会自动堆叠，每段用该任务的固定配色。
                    BarMark(
                        x: .value("日期", point.day, unit: .day),
                        y: .value("专注分钟", point.duration / 60),
                        width: .fixed(18)
                    )
                    .foregroundStyle(by: .value("任务", point.taskTitle))
                    .cornerRadius(3)
                    .accessibilityLabel("\(beijingDateString(point.day, dateStyle: .abbreviated, timeStyle: .omitted)) \(point.taskTitle)")
                    .accessibilityValue(formatHistoryDuration(point.duration))
                }
                .chartForegroundStyleScale(
                    domain: order,
                    range: order.map { title in
                        let hex = store.pomodoroTasks.first {
                            PomodoroTaskPalette.normalized($0.title) == title
                        }?.colorHex ?? PomodoroTaskPalette.fallbackColorHex(for: title)
                        return DataSignal.color(hex: hex, isDark: colorScheme == .dark)
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
            }
        }
        .padding(Space.l)
        .nestedSurface()
    }

    private var taskBreakdownCard: some View {
        let items = taskBreakdown
        let totalDuration = items.reduce(0.0) { $0 + $1.duration }
        let longest = items.first?.duration ?? 1

        return VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .firstTextBaseline) {
                Text("按任务分布")
                    .font(AppType.pageTitle(15))
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
                VStack(spacing: Space.s) {
                    ForEach(items.prefix(8), id: \.title) { item in
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
                                progress: CGFloat(min(1, item.duration / max(1, longest))),
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
            Text("查看时间范围")
                .font(AppType.caption(weight: .medium))
                .foregroundStyle(.secondary)

            TimeSlotSegmentedControl(
                options: PomodoroHistoryRange.allCases.map {
                    SegmentOption(id: $0.id, title: $0.title, value: $0)
                },
                selection: $historyRange,
                tint: stopwatchColor
            )

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
                    DatePicker("开始日期", selection: $customHistoryStart, displayedComponents: [.date])
                    DatePicker("结束日期", selection: $customHistoryEnd, displayedComponents: [.date])
                }
                .font(AppType.ui(Typo.footnote))
            }
        }
        .padding(Space.m)
        .nestedSurface()
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
        guard let bounds else { return record.actualDuration }
        let overlapStart = max(record.startedAt, bounds.start)
        let overlapEnd = min(record.endedAt, bounds.end)
        let overlap = max(0, overlapEnd.timeIntervalSince(overlapStart))
        let wallDuration = record.endedAt.timeIntervalSince(record.startedAt)
        guard wallDuration > 0 else { return overlap > 0 ? record.actualDuration : 0 }
        return record.actualDuration * min(1, overlap / wallDuration)
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
        if total < 60 { return "\(total)秒" }
        let minutes = total / 60
        let hours = minutes / 60
        if hours > 0 {
            return minutes % 60 == 0 ? "\(hours)小时" : "\(hours)小时\(minutes % 60)分"
        }
        return "\(minutes)分钟"
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
                            .font(AppType.caption(7, weight: .bold))
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
        DataSignal.color(hex: record.phase.colorHex, isDark: colorScheme == .dark)
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
            if total < 60 { return "\(total)秒" }
            let minutes = total / 60
            let seconds = total % 60
            return seconds == 0 ? "\(minutes)分钟" : "\(minutes)分\(seconds)秒"
        }
        let plannedMinutes = max(1, Int(record.plannedDuration / 60))
        if total < 60 { return "\(total)秒 / \(plannedMinutes)分" }
        return "\(total / 60)分\(total % 60)秒 / \(plannedMinutes)分"
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
                : task.colorHex,
            isDark: colorScheme == .dark
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

    private var durationText: String {
        let wall = max(0, endedAt.timeIntervalSince(startedAt))
        let total = Int(wall.rounded())
        if total < 60 { return "\(total) 秒" }
        let minutes = total / 60
        let hours = minutes / 60
        if hours > 0 {
            return minutes % 60 == 0 ? "\(hours) 小时" : "\(hours) 小时 \(minutes % 60) 分"
        }
        return "\(minutes) 分钟"
    }

    private var canSave: Bool {
        endedAt.timeIntervalSince(startedAt) > 0
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
                    Text("修正后时长")
                        .font(AppType.ui(Typo.footnote, .medium))
                    Spacer()
                    Text(durationText)
                        .font(AppType.ui(Typo.body, .semibold))
                        .monospacedDigit()
                        .foregroundStyle(canSave ? Color.primary : Color.orange)
                }

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
