import AppKit
import SwiftUI
import Combine
import WidgetKit

struct BrandMark: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            // 两条错位时间带，中央金色楔形就是“时隙”。
            RoundedRectangle(cornerRadius: size * 0.08, style: .continuous)
                .fill(Color.primary)
                .frame(width: size * 0.42, height: size * 0.14)
                .offset(x: -size * 0.10, y: -size * 0.08)

            RoundedRectangle(cornerRadius: size * 0.08, style: .continuous)
                .fill(Color.primary)
                .frame(width: size * 0.42, height: size * 0.14)
                .offset(x: size * 0.10, y: size * 0.08)

            TimeSlotWedge()
                .fill(
                    LinearGradient(
                        colors: [BrandPalette.goldHighlight, BrandPalette.gold],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: size * 0.16, height: size * 0.28)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}


/// 先给出调用时刻，再给出之后每个北京时间零点。
/// 起点不能直接是下一个零点：TimelineView 会立刻把那个未来时刻当成当前值。
struct BeijingDaySchedule: TimelineSchedule, Sendable {
    func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnySequence<Date> {
        AnySequence(BeijingDayEntries(start: startDate))
    }
}

private struct BeijingDayEntries: Sequence, IteratorProtocol, Sendable {
    private var upcoming: Date

    init(start: Date) {
        upcoming = start
    }

    mutating func next() -> Date? {
        let value = upcoming
        upcoming = FocusStats.nextDayBoundary(after: value)
        return value
    }
}

enum CountdownViewMode: String, CaseIterable, Identifiable {
    case card = "这个目标"
    case roadmap = "全部目标"

    var id: String { rawValue }
}

struct ContentView: View {
    @ObservedObject var store: CountdownStore
    @State private var showingAdd = false
    @State private var showingEdit = false
    @State private var showingWidgetHelp = false
    @State private var showingShortcuts = false
    @State private var showingWeeklyGoalSettings = false
    @State private var pendingDelete: CountdownItem?
    @State private var searchText = ""
    @State private var countdownViewMode: CountdownViewMode = .card
    @State private var editingHistoryRecord: PomodoroSessionRecord?
    @State private var pomodoroOpenRequest: PomodoroOpenRequest?
    @State private var selectedSection: TimeBookSection = .home
    @State private var hoveredRail: TimeBookSection?
    @FocusState private var searchFieldFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    /// 睡眠跨过零点时，TimelineView 可能停在昨天的条目上；回到前台时用它把日期拉回时钟。
    @State private var homeDayAnchor = Date.distantPast

    private var accent: Color { store.accentPreset.color }
    private var stopwatchColor: Color { store.accentPreset.color }

    var filteredItems: [CountdownItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.items }
        return store.items.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            navigationRail

            VStack(alignment: .leading, spacing: 16) {
                workstationHeader

                Group {
                    if selectedSection == .home {
                        GeometryReader { geo in
                            ScrollView {
                                homeDashboard
                                    .frame(maxWidth: .infinity, minHeight: max(0, geo.size.height), alignment: .top)
                            }
                            .scrollIndicators(.hidden)
                        }
                    } else {
                        HStack(alignment: .top, spacing: 14) {
                            detail
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .padding(.top, 10)
            .padding(.trailing, 18)
            .padding(.bottom, 18)
            .padding(.leading, 2)
        }
        .fontDesign(.default)
        .background {
            FrostedCanvas(theme: store.accentPreset)
        }
        .overlay(alignment: .bottomTrailing) {
            VStack(alignment: .trailing, spacing: Space.s) {
                if let action = store.undoableAction {
                    UndoBanner(action: action, accent: accent) {
                        store.undoLastAction()
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(.trailing, Space.xl)
            .padding(.bottom, Space.xl)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: store.undoableAction)
        .sheet(isPresented: $showingAdd) {
            CountdownEditor(mode: .add) { title, date, color in
                store.add(title: title, targetDate: date, colorHex: color)
            }
        }
        .sheet(isPresented: $showingEdit) {
            if let selected = store.selectedItem {
                CountdownEditor(mode: .edit(selected)) { title, date, color in
                    store.applyEdit(to: selected, title: title, targetDate: date, colorHex: color)
                }
            }
        }
        .sheet(isPresented: $showingWidgetHelp) {
            WidgetGuideSheet(store: store)
        }
        .sheet(isPresented: $showingShortcuts) {
            KeyboardShortcutsSheet()
        }
        .sheet(isPresented: $showingWeeklyGoalSettings) {
            WeeklyGoalSettingsView(
                goalHours: max(1, store.pomodoro.weeklyFocusGoalMinutes / 60),
                accent: store.accentPreset.color
            ) { hours in
                store.updateWeeklyFocusGoal(hours: hours)
            }
        }
        .sheet(item: $editingHistoryRecord) { record in
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
        .onReceive(NotificationCenter.default.publisher(for: .newCountdownRequested)) { _ in
            showingAdd = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToHomeRequested)) { _ in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                selectedSection = .home
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToCountdownRequested)) { _ in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                selectedSection = .countdown
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToPomodoroRequested)) { _ in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                selectedSection = .pomodoro
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showWidgetHelpRequested)) { _ in
            showingWidgetHelp = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showKeyboardShortcutsRequested)) { _ in
            showingShortcuts = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusCountdownSearchRequested)) { _ in
            selectedSection = .countdown
            searchFieldFocused = true
        }
        .alert(
            "删除「\(pendingDelete?.title ?? "")」？",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            )
        ) {
            Button("删除", role: .destructive) {
                if let pendingDelete {
                    store.delete(pendingDelete)
                }
                pendingDelete = nil
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("删除后可在 8 秒内撤销。桌面小组件会自动切换显示其他倒计时。")
                .lineSpacing(2.5)
        }
    }

    private var workstationHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 12) {
                BrandMark(size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text("TIMESLOT")
                        .font(.custom("Futura-Medium", fixedSize: 19))
                        .tracking(1.25)
                        .foregroundStyle(Color.primary.opacity(0.92))
                    Text(workspaceTitle)
                        .font(.custom("Futura-Medium", fixedSize: 8.5))
                        .tracking(1.25)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 2)

            Spacer(minLength: 16)

            Button {
                showingWidgetHelp = true
            } label: {
                Label("桌面小组件", systemImage: "macwindow.on.rectangle")
                    .font(AppType.ui(Typo.footnote, .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .buttonStyle(TimeSlotPressableStyle())
            .background(pillChrome)
            .help("1:1 预览桌面小组件")
        }
        .padding(.leading, 8)
    }

    private var pillChrome: some View {
        Capsule()
            .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.04))
            .overlay(Capsule().stroke(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08), lineWidth: 1))
    }

    private var workspaceTitle: String {
        switch selectedSection {
        case .home: return "WORKSPACE"
        case .countdown: return "COUNTDOWN"
        case .pomodoro: return "FOCUS"
        case .settings: return "SETTINGS"
        }
    }

    private func headerGhostButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(AppType.ui(Typo.footnote, .medium))
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .foregroundStyle(.primary.opacity(0.78))
        }
        .buttonStyle(TimeSlotPressableStyle())
        .inkPill()
    }

    private var navigationRail: some View {
        VStack(spacing: 18) {
            VStack(spacing: 10) {
                railButton(
                    title: "首页",
                    systemImage: "square.grid.2x2",
                    section: .home
                )
                railButton(
                    title: "倒计时",
                    systemImage: "calendar.badge.clock",
                    section: .countdown
                )
                railButton(
                    title: "专注",
                    systemImage: "timer",
                    section: .pomodoro
                )
                railButton(
                    title: "设置",
                    systemImage: "gearshape",
                    section: .settings
                )
            }
            .padding(.top, 24)

            Spacer(minLength: Space.xl)

            Button {
                showingShortcuts = true
            } label: {
                Image(systemName: "keyboard")
                    .font(AppType.ui(Typo.body, .medium))
                    .frame(width: 36, height: 36)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(TimeSlotPressableStyle())
            .help("快捷键速查 (⌘/)")
            .padding(.bottom, 22)
        }
        .frame(width: 76)
    }

    private func railButton(
        title: String,
        systemImage: String,
        section: TimeBookSection
    ) -> some View {
        let isSelected = selectedSection == section
        let isHovered = hoveredRail == section
        return Button {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                selectedSection = section
            }
        } label: {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(isSelected ? BrandPalette.gold : Color.clear)
                    .frame(width: 3, height: 28)

                VStack(spacing: 2) {
                    Image(systemName: systemImage)
                        .font(AppType.ui(16, .medium))
                    Text(title)
                        .font(AppType.caption(10, weight: isSelected ? .semibold : .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(isSelected ? Color.primary.opacity(0.92) : Color.primary.opacity(isHovered ? 0.78 : 0.62))
                .frame(width: 52, height: 44)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(colorScheme == .dark ? 0.14 : 0.78))
                    }
                }
            }
            .frame(width: 64, height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(TimeSlotPressableStyle())
        .onHover { hovering in
            hoveredRail = hovering ? section : nil
        }
        .help(title)
        .accessibilityLabel(title)
        .accessibilityIdentifier("timeslot.navigation.\(section.rawValue)")
        .accessibilityValue(isSelected ? "已选中" : "未选中")
    }

    private var homeDashboard: some View {
        TimelineView(BeijingDaySchedule()) { context in
            homeDashboardContent(
                at: FocusStats.displayInstant(scheduleDate: context.date, anchor: homeDayAnchor)
            )
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                homeDayAnchor = Date()
            }
        }
    }

    private func homeDashboardContent(at now: Date) -> some View {
        VStack(alignment: .leading, spacing: Space.l) {
            homeCommandDeck(at: now)
            homeCalendarBoard(at: now)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, Space.xl)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func homeCommandDeck(at now: Date) -> some View {
        let next = upcomingCountdowns.first ?? store.selectedItem ?? store.items.first
        let state = store.pomodoro

        let todayBounds = FocusStats.todayBounds(containing: now)
        let todaySaved = FocusStats.totalSeconds(
            in: store.pomodoroHistory,
            from: todayBounds.start,
            to: todayBounds.end
        )
        let pace = FocusStats.weekPace(
            in: store.pomodoroHistory,
            goalMinutes: store.pomodoro.weeklyFocusGoalMinutes,
            at: now
        )
        let taskName = state.taskTitle.isEmpty ? "当前任务" : state.taskTitle
        let sessionOpen = state.isStopwatchActive || (state.phase == .focus && state.sessionStartedAt != nil)
        return HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: Space.s) {
                HStack {
                    Text("今天已记录")
                        .font(AppType.ui(Typo.footnote, .medium))
                        .foregroundStyle(Color.primary.opacity(0.72))
                    Spacer()
                    Button {
                        pomodoroOpenRequest = .todayInsights
                        selectedSection = .pomodoro
                    } label: {
                        Label("今天的统计", systemImage: "arrow.up.right")
                            .font(AppType.caption(12, weight: .medium))
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("打开今天的统计")
                }
                Text(FocusStats.durationText(todaySaved))
                    .font(AppType.timer(40))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(taskName)
                    .font(AppType.ui(Typo.body, .medium))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Button {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.75)) {
                            if state.isStopwatchActive {
                                store.startOrPauseStopwatch()
                            } else {
                                store.startOrPausePomodoro()
                            }
                        }
                    } label: {
                        let isLive = state.isStopwatchActive ? state.stopwatchRunning : state.isRunning
                        Label(isLive ? "暂停" : (sessionOpen ? "继续" : "开始"), systemImage: isLive ? "pause.fill" : "play.fill")
                            .font(AppType.ui(Typo.footnote, .semibold))
                    }
                    .buttonStyle(TimeSlotPrimaryActionStyle())
                    .accessibilityIdentifier("timeslot.home.focus.start-pause")
                    if sessionOpen {
                        Button {
                            if state.isStopwatchActive {
                                store.stopStopwatch()
                            } else {
                                store.stopPomodoro()
                            }
                        } label: {
                            Label("结束并记录", systemImage: "stop.fill")
                                .font(AppType.ui(Typo.footnote, .medium))
                        }
                        .buttonStyle(TimeSlotPressableStyle())
                        .inkPill()
                        .help("结束当前计时。满 10 秒才写入学习记录。")
                        .accessibilityLabel("结束并记录")
                    }
                }
                let focusIsRunning = state.isStopwatchActive ? state.stopwatchRunning : state.isRunning
                if focusIsRunning {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        homeFocusReadout(state: state, date: context.date)
                    }
                } else {
                    homeFocusReadout(state: state, date: Date())
                }
                if sessionOpen {
                    TimelineView(.periodic(from: .now, by: 15)) { context in
                        let live = FocusStats.openSessionSeconds(state, at: context.date)
                        Text("本次进行中 \(max(0, Int(live / 60))) 分钟，结束后计入。未写入今日已记录。")
                            .font(AppType.caption())
                            .foregroundStyle(Color.primary.opacity(0.78))
                    }
                }
                HStack(spacing: 6) {
                    Text("本周 \(FocusStats.durationText(pace.savedSeconds)) / \(max(1, store.pomodoro.weeklyFocusGoalMinutes / 60)) 小时")
                        .font(AppType.caption())
                        .foregroundStyle(Color.primary.opacity(0.78))
                    Button {
                        showingWeeklyGoalSettings = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(AppType.caption(11, weight: .semibold))
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("修改每周专注目标")
                    .accessibilityIdentifier("timeslot.home.weekly-goal.edit")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)

            Divider()
                .padding(.horizontal, Space.l)

            VStack(alignment: .leading, spacing: Space.s) {
                HStack {
                    Text("下一目标")
                        .font(AppType.caption())
                        .foregroundStyle(Color.primary.opacity(0.72))
                    Spacer()
                    Button {
                        if next == nil {
                            showingAdd = true
                        } else {
                            selectedSection = .countdown
                        }
                    } label: {
                        Image(systemName: next == nil ? "plus" : "arrow.up.right")
                            .font(AppType.caption(12, weight: .semibold))
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(next == nil ? "新建倒计时" : "打开倒计时")
                }
                if let next {
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        let remaining = next.remaining(at: context.date)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(next.title)
                                .font(AppType.ui(Typo.body, .medium))
                                .lineLimit(1)
                            Text(remaining > 0 ? homeRemaining(remaining) : "已到达")
                                .font(AppType.ui(22, .semibold))
                                .monospacedDigit()
                            Text(beijingDateString(next.targetDate, dateStyle: .abbreviated, timeStyle: .omitted))
                                .font(AppType.caption())
                                .foregroundStyle(Color.primary.opacity(0.72))
                        }
                    }
                } else {
                    Text("建立一个目标")
                        .font(AppType.ui(Typo.body, .medium))
                }
            }
            .frame(width: 180, alignment: .leading)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .background {
            RoundedRectangle(cornerRadius: Radius.board, style: .continuous)
                .fill(Surface.board)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Radius.board, style: .continuous)
                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.22 : 0.06), radius: 16, y: 6)
    }

    @ViewBuilder
    private func homeCalendarBoard(at now: Date) -> some View {
        let hasLiveBlock = store.pomodoro.isStopwatchActive
            || (store.pomodoro.isRunning && store.pomodoro.phase == .focus)
        if hasLiveBlock {
            // 只有进行中的记录需要每分钟延长任务块；空闲时让整张时间轴保持静态。
            TimelineView(.periodic(from: .now, by: 60)) { context in
                homeHourTimeline(at: context.date)
            }
        } else {
            // 空闲时间轴按天固定。外层 BeijingDaySchedule 在零点传入新的一天，不在这里跟秒走。
            homeHourTimeline(at: beijingCalendar.startOfDay(for: now))
        }
    }

    private func homeHourTimeline(at date: Date) -> some View {
        HomeHourTimeline(
            store: store,
            currentDate: date,
            onOpenFocus: {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                    selectedSection = .pomodoro
                }
            },
            onEditRecordIDs: { ids in
                if let id = ids.first, let record = store.pomodoroHistory.first(where: { $0.id == id }) {
                    editingHistoryRecord = record
                }
            }
        )
    }


    private var upcomingCountdowns: [CountdownItem] {
        let now = Date()
        return store.items
            .filter { !$0.isPaused && $0.remaining(at: now) > 0 }
            .sorted { $0.targetDate < $1.targetDate }
    }

    private func homePomodoroClock(_ remaining: TimeInterval) -> String {
        let total = max(0, Int(ceil(remaining)))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private func homeRemaining(_ remaining: TimeInterval) -> String {
        let total = max(0, Int(ceil(remaining)))
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        if days > 0 { return "\(days) 天" }
        if hours > 0 { return "\(hours) 小时" }
        return "\(minutes) 分"
    }

    private func homeStopwatchText(_ elapsed: TimeInterval) -> String {
        let total = max(0, Int(elapsed))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func homeFocusReadout(state: PomodoroState, date: Date) -> some View {
        let isStopwatch = state.isStopwatchActive
        let isRunning = isStopwatch ? state.stopwatchRunning : state.isRunning
        let time = isStopwatch
            ? homeStopwatchText(state.stopwatchElapsed(at: date))
            : homePomodoroClock(state.remaining(at: date))
        let progress = isStopwatch
            ? CGFloat((state.stopwatchElapsed(at: date).truncatingRemainder(dividingBy: 60)) / 60)
            : CGFloat(min(1, max(0, state.elapsed(at: date) / max(1, state.duration(for: state.phase)))))
        let task = state.taskTitle.isEmpty ? "当前任务" : state.taskTitle

        return VStack(alignment: .leading, spacing: Space.s) {
            Text(task)
                .font(AppType.ui(Typo.body, .medium))
                .lineLimit(1)
            Text(time)
                .font(AppType.timer(34))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(isRunning ? "正在计时" : (isStopwatch ? "等待继续" : "下一次专注"))
                .font(AppType.caption())
                .foregroundStyle(isRunning ? store.accentPreset.color : .secondary)
            TimeSlotProgressBar(
                progress: progress,
                color: store.accentPreset.color,
                height: 6,
                showsKnob: false,
                animatesProgress: false
            )
        }
    }

    @ViewBuilder
    private var detail: some View {
        Group {
            if selectedSection == .countdown {
                countdownDetail
            } else if selectedSection == .pomodoro {
                PomodoroView(
                    store: store,
                    onSyncWidget: syncPomodoroToDesktop,
                    openRequest: $pomodoroOpenRequest
                )
            } else {
                AppSettingsPage(store: store)
            }
        }
        .id(selectedSection)
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.988)))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(colorScheme == .dark ? Color(nsColor: .windowBackgroundColor) : Color.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 18))
    }

    private var countdownDetail: some View {
        return VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("倒计时")
                            .font(AppType.caption())
                            .foregroundStyle(.secondary)
                        Text(store.selectedItem?.title ?? "时隙")
                            .font(AppType.pageTitle(28))
                            .tracking(-0.4)
                            .lineLimit(1)
                    }
                    Spacer()

                    HStack(spacing: Space.s) {
                        Image(systemName: "magnifyingglass")
                            .font(AppType.caption(12, weight: .medium))
                            .foregroundStyle(.secondary)
                        TextField("搜索倒计时", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(AppType.ui(Typo.footnote))
                            .focused($searchFieldFocused)
                            .frame(width: 140)
                            .accessibilityIdentifier("timeslot.countdown.search")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.045),
                        in: Capsule()
                    )

                    if let selected = store.selectedItem {
                        Menu {
                            ForEach(filteredItems) { item in
                                Button(item.title) { store.selectedID = item.id }
                            }
                            if filteredItems.isEmpty {
                                Text("没有匹配的目标")
                            }
                            Divider()
                            Button("新建倒计时") { showingAdd = true }
                        } label: {
                            Label("切换目标", systemImage: "list.bullet")
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .accessibilityIdentifier("timeslot.countdown.targets")

                        QuickActionButton(
                            title: selected.isPaused ? "继续" : "暂停",
                            icon: selected.isPaused ? "play.fill" : "pause.fill",
                            tint: accent
                        ) { store.togglePause(selected) }

                        Menu {
                            Button("编辑…", systemImage: "slider.horizontal.3") {
                                showingEdit = true
                            }
                            Button(
                                selected.isPinned ? "从桌面小组件移除" : "固定到桌面小组件",
                                systemImage: selected.isPinned ? "rectangle.slash" : "rectangle.on.rectangle"
                            ) {
                                pinToDesktop(selected)
                            }
                            Divider()
                            Button("删除倒计时", role: .destructive) {
                                pendingDelete = selected
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(AppType.caption(12, weight: .medium))
                                .frame(width: 28, height: 28)
                                .foregroundStyle(.secondary)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .accessibilityLabel("更多操作")
                        .accessibilityIdentifier("timeslot.countdown.more")
                    }
                }
                .padding(.horizontal, Space.xxl)
                .padding(.top, Space.xxl)
                .padding(.bottom, Space.l)

                TimeSlotSegmentedControl(
                    options: CountdownViewMode.allCases.map {
                        SegmentOption(id: $0.rawValue, title: $0.rawValue, value: $0)
                    },
                    selection: $countdownViewMode,
                    tint: accent
                )
                .frame(width: 220)
                .padding(.horizontal, Space.xxl)
                .padding(.bottom, Space.l)

                if countdownViewMode == .roadmap {
                    CountdownRoadmapTimelineView(
                        store: store,
                        onSelect: { item in
                            store.selectedID = item.id
                            withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8)) {
                                countdownViewMode = .card
                            }
                        },
                        onEdit: { item in
                            store.selectedID = item.id
                            showingEdit = true
                        }
                    )
                    .padding(.horizontal, Space.xxl)
                    .padding(.bottom, Space.xxl)
                } else if let selected = store.selectedItem {
                    ScrollView {
                        HStack(alignment: .top, spacing: 0) {
                            CountdownHero(item: selected, accent: accent)
                                .frame(maxWidth: .infinity)

                            Divider()
                                .padding(.vertical, Space.xl)

                            countdownInfoPanel(selected)
                                .frame(width: 232)
                        }
                        .frame(maxWidth: 1040)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, Space.xxl)
                        .padding(.bottom, Space.xxl)
                    }
                    .scrollIndicators(.hidden)
                } else {
                    VStack(spacing: Space.m) {
                        BrandMark(size: 52)
                            .opacity(0.85)
                        Text("还没有倒计时")
                            .font(AppType.ui(Typo.headline, .medium))
                        Text("记录考试、发布、旅行，或任何一件值得等待的事。")
                            .font(AppType.ui(Typo.body))
                            .lineSpacing(2)
                            .foregroundStyle(.secondary)
                        Button {
                            showingAdd = true
                        } label: {
                            Text("新建倒计时")
                                .font(AppType.ui(Typo.footnote, .medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .foregroundStyle(.primary.opacity(0.78))
                        }
                        .buttonStyle(TimeSlotPressableStyle())
                        .inkPill()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }

    private func countdownInfoPanel(_ item: CountdownItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Space.s) {
                Text("目标时刻")
                    .font(AppType.ui(Typo.footnote, .medium))
                    .foregroundStyle(.secondary)
                Text(beijingDateString(item.targetDate, dateStyle: .long, timeStyle: .omitted))
                    .font(AppType.title(Typo.headline))
                Text(beijingDateString(item.targetDate, dateStyle: .omitted, timeStyle: .shortened) + " · 北京时间")
                    .font(AppType.caption())
                    .foregroundStyle(.secondary)
            }

            Divider().padding(.vertical, Space.m)
            VStack(alignment: .leading, spacing: Space.s) {
                Text("建立于")
                    .font(AppType.caption())
                    .foregroundStyle(.secondary)
                Text(beijingDateString(item.createdAt, dateStyle: .long, timeStyle: .omitted))
                    .font(AppType.ui(Typo.footnote, .medium))
            }
            Divider().padding(.vertical, Space.m)

            VStack(alignment: .leading, spacing: Space.m) {
                countdownStatusRow(
                    title: "桌面小组件",
                    value: item.isPinned ? "当前展示" : "未展示",
                    icon: item.isPinned ? "rectangle.3.group.fill" : "rectangle.3.group"
                )
            }
        }
        .padding(.vertical, Space.xl)
        .padding(.horizontal, Space.l)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func countdownStatusRow(title: String, value: String, icon: String) -> some View {
        HStack(spacing: Space.m) {
            Image(systemName: icon)
                .font(AppType.ui(Typo.footnote, .medium))
                .foregroundStyle(accent)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppType.caption())
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(AppType.ui(Typo.footnote, .medium))
            }
            Spacer(minLength: 0)
        }
    }

    private func pinToDesktop(_ item: CountdownItem) {
        store.selectForDesktopWidget(item)
        showingWidgetHelp = true
    }

    private func syncPomodoroToDesktop() {
        store.selectPomodoroForDesktopWidget()
        showingWidgetHelp = true
    }
}

/// 多目标时间流全景视图 (Timeline Roadmap View)
struct CountdownRoadmapTimelineView: View {
    @ObservedObject var store: CountdownStore
    let onSelect: (CountdownItem) -> Void
    let onEdit: (CountdownItem) -> Void

    private var accent: Color { store.accentPreset.color }

    private struct RoadmapGroup: Identifiable {
        let id: String
        let title: String
        let icon: String
        let color: Color
        let items: [CountdownItem]

        init(title: String, icon: String, color: Color, items: [CountdownItem]) {
            self.id = title
            self.title = title
            self.icon = icon
            self.color = color
            self.items = items
        }
    }

    private var groups: [RoadmapGroup] {
        let now = Date()
        let sorted = store.items.sorted { $0.targetDate < $1.targetDate }
        var within7: [CountdownItem] = []
        var thisMonth: [CountdownItem] = []
        var later: [CountdownItem] = []
        var completed: [CountdownItem] = []

        for item in sorted {
            let rem = item.remaining(at: now)
            if rem <= 0 && !item.isPaused {
                completed.append(item)
            } else if rem < 7 * 86400 {
                within7.append(item)
            } else if rem < 31 * 86400 {
                thisMonth.append(item)
            } else {
                later.append(item)
            }
        }

        var result: [RoadmapGroup] = []
        if !within7.isEmpty {
            result.append(RoadmapGroup(title: "7 天内即将到达", icon: "flame.fill", color: .orange, items: within7))
        }
        if !thisMonth.isEmpty {
            result.append(RoadmapGroup(title: "本月到期", icon: "calendar.badge.clock", color: accent, items: thisMonth))
        }
        if !later.isEmpty {
            result.append(RoadmapGroup(title: "未来更长时间", icon: "star.fill", color: DataGradient.base(4), items: later))
        }
        if !completed.isEmpty {
            result.append(RoadmapGroup(title: "已到达目标", icon: "checkmark.circle.fill", color: BrandPalette.success, items: completed))
        }
        return result
    }

    var body: some View {
        // 分组、状态徽章和进度条都只显示到分钟；秒级刷新只会重排整个滚动区。
        TimelineView(.periodic(from: .now, by: 60)) { context in
            ScrollView {
                if groups.isEmpty {
                    VStack(spacing: Space.m) {
                        Image(systemName: "calendar.badge.plus")
                            .font(AppType.ui(36))
                            .foregroundStyle(accent)
                        Text("时间流暂无目标")
                            .font(AppType.ui(Typo.headline, .medium))
                        Text("添加倒计时后，这里会以全景时间轴展示所有关键节点。")
                            .font(AppType.ui(Typo.body))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    VStack(alignment: .leading, spacing: Space.xl) {
                        horizonAxis

                        ForEach(groups) { group in
                            VStack(alignment: .leading, spacing: Space.m) {
                                HStack(spacing: Space.s) {
                                    Image(systemName: group.icon)
                                        .font(AppType.ui(Typo.footnote, .semibold))
                                        .foregroundStyle(group.color)
                                    Text(group.title)
                                        .font(AppType.ui(Typo.body, .semibold))
                                    Spacer()
                                    Text("\(group.items.count) 个目标")
                                        .font(AppType.caption())
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, Space.s)

                                VStack(spacing: 0) {
                                    ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                                        RoadmapItemRow(
                                            item: item,
                                            currentDate: context.date,
                                            isLast: index == group.items.count - 1,
                                            onSelect: { onSelect(item) },
                                            onEdit: { onEdit(item) },
                                            onTogglePause: { store.togglePause(item) }
                                        )
                                    }
                                }
                                .padding(Space.m)
                                .cardSurface(cornerRadius: Radius.medium)
                            }
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    /// 顶部全景轴：把「今天 → 最远目标」画成一根真实时间轴，
    /// 让「时间流全景」不再只是分组列表，每个目标的位置就是它的到期远近。
    private var horizonAxis: some View {
        let now = Date()
        let active = store.items
            .filter { $0.remaining(at: now) > 0 }
            .sorted { $0.targetDate < $1.targetDate }
        let horizon = active.last?.targetDate ?? now.addingTimeInterval(30 * 86_400)
        let span = max(1, horizon.timeIntervalSince(now))

        return VStack(alignment: .leading, spacing: Space.m) {
            HStack {
                Label("时间轴", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(AppType.ui(Typo.footnote, .medium))
                Spacer()
                Text("今天 → \(beijingDateString(horizon, dateStyle: .abbreviated, timeStyle: .omitted))")
                    .font(AppType.caption())
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Surface.track)
                        .frame(height: 4)
                        .position(x: proxy.size.width / 2, y: 9)

                    ForEach(active) { item in
                        let ratio = min(1, max(0, item.targetDate.timeIntervalSince(now) / span))
                        Circle()
                            .fill(DataSignal.color(hex: item.colorHex))
                            .frame(width: 11, height: 11)
                            .overlay(Circle().stroke(Color.primary.opacity(0.18), lineWidth: 1))
                            .position(x: max(6, min(proxy.size.width - 6, proxy.size.width * ratio)), y: 9)
                            .help("\(item.title) · \(beijingDateString(item.targetDate, dateStyle: .abbreviated, timeStyle: .omitted))")
                    }

                    Circle()
                        .fill(Color.primary.opacity(0.55))
                        .frame(width: 6, height: 6)
                        .position(x: 3, y: 9)
                }
            }
            .frame(height: 18)

            HStack {
                Text("今天")
                Spacer()
                if let last = active.last {
                    Text("最远 \(last.title)")
                }
            }
            .font(AppType.caption(11))
            .foregroundStyle(.secondary)
        }
        .padding(Space.m)
        .cardSurface()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            active.isEmpty
                ? "时间轴暂无目标"
                : "时间轴：今天起，" + active.map {
                    "\($0.title) \(beijingDateString($0.targetDate, dateStyle: .abbreviated, timeStyle: .omitted))"
                }.joined(separator: "，")
        )
    }
}

private struct RoadmapItemRow: View {
    let item: CountdownItem
    let currentDate: Date
    let isLast: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onTogglePause: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var itemColor: Color {
        DataSignal.color(hex: item.colorHex)
    }

    var body: some View {
        HStack(alignment: .top, spacing: Space.m) {
            // 时间轴轨道与节点
            VStack(spacing: 0) {
                Circle()
                    .fill(itemColor)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(Color.primary.opacity(0.15), lineWidth: 1.5))
                    .shadow(color: itemColor.opacity(0.4), radius: 4)

                if !isLast {
                    Rectangle()
                        .fill(itemColor.opacity(0.25))
                        .frame(width: 2)
                        .frame(minHeight: 48)
                }
            }
            .frame(width: 16)
            .padding(.top, 4)

            // 卡片内容
            VStack(alignment: .leading, spacing: Space.s) {
                HStack(alignment: .center) {
                    Text(item.title)
                        .font(AppType.ui(Typo.body, .semibold))
                        .foregroundStyle(.primary)

                    Spacer()

                    let remaining = item.remaining(at: currentDate)
                    let isDone = remaining <= 0
                    StatusPillBadge(
                        title: item.isPaused ? "已暂停" : (isDone ? "已达成" : formatRemaining(remaining)),
                        icon: item.isPaused ? "pause.circle" : (isDone ? "checkmark.circle.fill" : nil),
                        color: item.isPaused ? .secondary : (isDone ? BrandPalette.success : itemColor)
                    )
                }

                HStack {
                    Label(beijingDateString(item.targetDate, dateStyle: .long, timeStyle: .shortened), systemImage: "calendar")
                        .font(AppType.caption())
                        .foregroundStyle(.secondary)
                    Spacer()
                    HStack(spacing: 8) {
                        Button {
                            onTogglePause()
                        } label: {
                            Image(systemName: item.isPaused ? "play.fill" : "pause.fill")
                                .font(AppType.caption(11, weight: .semibold))
                                .frame(width: 22, height: 22)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .accessibilityLabel(item.isPaused ? "继续倒计时" : "暂停倒计时")
                        .help(item.isPaused ? "继续" : "暂停")

                        Button {
                            onEdit()
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                                .font(AppType.caption(11, weight: .semibold))
                                .frame(width: 22, height: 22)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .accessibilityLabel("编辑倒计时")
                        .help("编辑")

                        Button("查看详情") {
                            onSelect()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(itemColor)
                        .controlSize(.mini)
                    }
                }

                let remaining = item.remaining(at: currentDate)
                let total = max(1, item.totalDuration)
                let progress = remaining <= 0 ? 1.0 : min(1.0, max(0.02, 1.0 - remaining / total))
                TimeSlotProgressBar(
                    progress: CGFloat(progress),
                    color: itemColor,
                    height: 5,
                    showsKnob: false
                )
            }
            .padding(Space.m)
            .nestedSurface()
        }
        .padding(.vertical, 4)
    }

    private func formatRemaining(_ remaining: TimeInterval) -> String {
        let total = max(0, Int(ceil(remaining)))
        let d = total / 86400
        let h = (total % 86400) / 3600
        let m = (total % 3600) / 60
        if d > 0 { return "剩 \(d) 天 \(h) 小时" }
        if h > 0 { return "剩 \(h) 小时 \(m) 分" }
        return "剩 \(m) 分"
    }
}

/// 快捷键速查面板
struct KeyboardShortcutsSheet: View {
    @Environment(\.dismiss) private var dismiss

    private struct ShortcutItem: Identifiable {
        let id = UUID()
        let keys: [String]
        let description: String
    }

    private let generalShortcuts: [ShortcutItem] = [
        ShortcutItem(keys: ["⌘", "0"], description: "回到首页"),
        ShortcutItem(keys: ["⌘", "1"], description: "切换至倒计时"),
        ShortcutItem(keys: ["⌘", "2"], description: "切换至番茄钟"),
        ShortcutItem(keys: ["⌘", "N"], description: "新建倒计时"),
        ShortcutItem(keys: ["⌘", "F"], description: "搜索倒计时"),
        ShortcutItem(keys: ["⌘", "/"], description: "打开快捷键指南"),
        ShortcutItem(keys: ["Esc"], description: "关闭弹窗 / 取消")
    ]

    private let timerShortcuts: [ShortcutItem] = [
        ShortcutItem(keys: ["Space"], description: "开始 / 暂停当前计时"),
        ShortcutItem(keys: ["R"], description: "重置当前计时"),
        ShortcutItem(keys: ["S"], description: "跳过当前番茄钟阶段")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.m) {
                BrandMark(size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text("快捷键指南")
                        .font(AppType.title(Typo.sheetTitle))
                    Text("全键盘高效掌控时隙")
                        .font(AppType.caption())
                        .foregroundStyle(.secondary)
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
            .padding(Space.xl)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    VStack(alignment: .leading, spacing: Space.m) {
                        Text("通用快捷键")
                            .font(AppType.ui(Typo.footnote, .semibold))
                            .foregroundStyle(.secondary)
                        ForEach(generalShortcuts) { item in
                            shortcutRow(item)
                        }
                    }
                    .padding(Space.l)
                    .nestedSurface()

                    VStack(alignment: .leading, spacing: Space.m) {
                        Text("计时与控制")
                            .font(AppType.ui(Typo.footnote, .semibold))
                            .foregroundStyle(.secondary)
                        ForEach(timerShortcuts) { item in
                            shortcutRow(item)
                        }
                    }
                    .padding(Space.l)
                    .nestedSurface()
                }
                .padding(Space.xl)
            }
            .scrollIndicators(.hidden)

            Divider()

            HStack {
                Spacer()
                Button("完成") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(Space.xl)
        }
        .frame(width: 460, height: 490)
    }

    private func shortcutRow(_ item: ShortcutItem) -> some View {
        HStack {
            Text(item.description)
                .font(AppType.ui(Typo.body))
            Spacer()
            HStack(spacing: 4) {
                ForEach(item.keys, id: \.self) { key in
                    Text(key)
                        .font(AppType.caption(12, weight: .semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .stroke(Color.primary.opacity(0.14), lineWidth: 1)
                        )
                }
            }
        }
    }
}

struct UndoBanner: View {
    let action: UndoableStoreAction
    let accent: Color
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: Space.m) {
            Image(systemName: "arrow.uturn.backward.circle.fill")
                .font(AppType.ui(Typo.body, .medium))
                .foregroundStyle(accent)

            Text(action.message)
                .font(AppType.ui(Typo.footnote, .medium))
                .lineLimit(1)

            Button("撤销", action: onUndo)
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .controlSize(.small)
                .accessibilityIdentifier("timeslot.undo")
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.s)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(accent.opacity(0.2), lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(action.message)
    }
}

private struct WidgetGuideSheet: View {
    @ObservedObject var store: CountdownStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: Int = 0

    private var accent: Color { store.accentPreset.color }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.m) {
                BrandMark(size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("桌面小组件")
                        .font(AppType.title(Typo.sheetTitle))
                    Text("实时 1:1 模拟预览与添加指南")
                        .font(AppType.caption())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .help("关闭")
                .accessibilityLabel("关闭")
                .keyboardShortcut(.cancelAction)
            }
            .padding(Space.xl)

            TimeSlotSegmentedControl(
                options: [
                    SegmentOption(id: "simulator", title: "1:1 桌面效果模拟", value: 0),
                    SegmentOption(id: "guide", title: "添加步骤说明", value: 1)
                ],
                selection: $selectedTab,
                tint: accent
            )
            .padding(.horizontal, Space.xl)
            .padding(.bottom, Space.m)

            Divider()

            if selectedTab == 0 {
                InteractiveWidgetSimulatorView(store: store)
            } else {
                guideStepsContent
            }

            Divider()

            HStack {
                Button("立即刷新桌面组件") {
                    store.refreshDesktopWidgets()
                }
                .buttonStyle(.bordered)
                Spacer()
                Button("完成") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(Space.xl)
        }
        .frame(width: 540)
    }

    private var guideStepsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                HStack(spacing: Space.m) {
                    Image(systemName: syncInfo.icon)
                        .font(AppType.ui(Typo.body, .semibold))
                        .foregroundStyle(syncInfo.color)
                        .frame(width: 30, height: 30)
                        .background(
                            syncInfo.color.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(syncInfo.title)
                            .font(AppType.ui(Typo.footnote, .semibold))
                        Text(syncInfo.subtitle)
                            .font(AppType.caption())
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(Space.m)
                .nestedSurface()

                VStack(alignment: .leading, spacing: Space.l) {
                    WidgetGuideStep(
                        number: 1,
                        title: "打开小组件库",
                        detail: "在 Mac 桌面空白处右键，选择“编辑小组件”。",
                        accent: accent
                    )
                    WidgetGuideStep(
                        number: 2,
                        title: "搜索“时隙”",
                        detail: "在左侧搜索框输入时隙，打开时隙的小组件集合。",
                        accent: accent
                    )
                    WidgetGuideStep(
                        number: 3,
                        title: "选择类型与尺寸",
                        detail: "点击或拖动小号、中号或大号组件到桌面。",
                        accent: accent
                    )
                    WidgetGuideStep(
                        number: 4,
                        title: "分别设置倒计时目标",
                        detail: "添加“时隙 · 自定义”后，右键每个组件选择“编辑小组件”，即可绑定不同倒计时。",
                        accent: accent
                    )
                }
            }
            .padding(Space.xl)
        }
        .scrollIndicators(.hidden)
    }

    private var syncInfo: (title: String, subtitle: String, icon: String, color: Color) {
        switch store.widgetSyncState {
        case .checking:
            return ("正在检查共享空间", "完成后即可在桌面显示最新内容。", "arrow.triangle.2.circlepath", .secondary)
        case .ready(let date):
            let time = beijingDateString(date, dateStyle: .omitted, timeStyle: .shortened)
            return ("小组件同步正常", "最近同步于 \(time)", "checkmark.circle.fill", accent)
        case .unavailable:
            return ("共享空间不可用", "请重新安装当前版本以恢复小组件权限。", "exclamationmark.triangle.fill", .orange)
        case .failed(let message):
            return ("小组件同步失败", message, "exclamationmark.circle.fill", .red)
        }
    }
}

/// 1:1 桌面小组件实时仿真模拟器
private struct InteractiveWidgetSimulatorView: View {
    @ObservedObject var store: CountdownStore
    @State private var simulatorSize: WidgetSimulatorSize = .medium
    @Environment(\.colorScheme) private var colorScheme

    private enum WidgetSimulatorSize: String, CaseIterable, Identifiable {
        case small = "小号 (170×170)"
        case medium = "中号 (364×170)"
        case large = "大号 (364×382)"

        var id: String { rawValue }
    }

    private var activeItem: CountdownItem? {
        store.selectedItem ?? store.items.first
    }

    var body: some View {
        VStack(spacing: Space.l) {
            TimeSlotSegmentedControl(
                options: WidgetSimulatorSize.allCases.map {
                    SegmentOption(id: $0.rawValue, title: $0.rawValue, value: $0)
                },
                selection: $simulatorSize,
                tint: store.accentPreset.color
            )
            .padding(.horizontal, Space.xl)

            // 预览只模拟桌面层级，避免另一套装饰性壁纸语言抢走组件本身。
            ZStack {
                RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.07))
                    .frame(maxWidth: .infinity, minHeight: 240)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                            .stroke(Color.primary.opacity(colorScheme == .dark ? 0.15 : 0.10), lineWidth: 1)
                    )

                TimelineView(.periodic(from: .now, by: 60)) { context in
                    renderedSimulatorWidget(at: context.date)
                        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.26 : 0.16), radius: 14, y: 6)
                }
            }
            .padding(.horizontal, Space.xl)

            Text("在桌面放置后，组件会跟随系统时钟秒级精准刷新。")
                .font(AppType.caption())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, Space.l)
    }

    @ViewBuilder
    private func renderedSimulatorWidget(at date: Date) -> some View {
        let item = activeItem
        let accent = item.map {
            DataSignal.color(hex: $0.colorHex)
        } ?? store.accentPreset.color
        let title = item?.title ?? "重要时刻"

        switch simulatorSize {
        case .small:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    BrandMark(size: 18)
                    Spacer()
                    Image(systemName: "timer")
                        .foregroundStyle(accent)
                }
                Spacer()
                Text(title)
                    .font(AppType.ui(Typo.footnote, .semibold))
                    .lineLimit(1)
                let rem = item?.remaining(at: date) ?? 3600
                Text(rem > 0 ? "\(max(0, Int(rem / 86400))) 天" : "已到达")
                    .font(AppType.timer(24))
                    .foregroundStyle(accent)
            }
            .padding(16)
            .frame(width: 155, height: 155)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))

        case .medium:
            HStack(spacing: 16) {
                ZStack {
                    let rem = item?.remaining(at: date) ?? 3600
                    let total = max(1, item?.totalDuration ?? 3600)
                    let prog = CGFloat(rem <= 0 ? 1.0 : min(1.0, max(0.02, 1.0 - rem / total)))
                    TimeSlotRing(progress: prog, color: accent, lineWidth: 8, showsGlow: true)
                        .frame(width: 90, height: 90)

                    Image(systemName: "timer")
                        .font(AppType.ui(24))
                        .foregroundStyle(accent)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        BrandMark(size: 16)
                        Text(title)
                            .font(AppType.ui(Typo.body, .semibold))
                            .lineLimit(1)
                    }
                    let rem = item?.remaining(at: date) ?? 3600
                    let d = max(0, Int(rem / 86400))
                    let h = (Int(rem) % 86400) / 3600
                    Text(rem > 0 ? "\(d)天 \(h)小时" : "目标达成")
                        .font(AppType.timer(24))
                        .monospacedDigit()
                        .foregroundStyle(accent)
                    if let targetDate = item?.targetDate {
                        Text(beijingDateString(targetDate, dateStyle: .abbreviated, timeStyle: .shortened))
                            .font(AppType.caption())
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(18)
            .frame(width: 330, height: 155)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))

        case .large:
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    BrandMark(size: 20)
                    Text(title)
                        .font(AppType.ui(Typo.body, .semibold))
                    Spacer()
                    Image(systemName: "macwindow.on.rectangle")
                        .foregroundStyle(accent)
                }

                HStack(spacing: 20) {
                    ZStack {
                        let rem = item?.remaining(at: date) ?? 3600
                        let total = max(1, item?.totalDuration ?? 3600)
                        let prog = CGFloat(rem <= 0 ? 1.0 : min(1.0, max(0.02, 1.0 - rem / total)))
                        TimeSlotRing(progress: prog, color: accent, lineWidth: 10, showsGlow: true)
                            .frame(width: 100, height: 100)

                        Image(systemName: "timer")
                            .font(AppType.ui(28))
                            .foregroundStyle(accent)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        let rem = item?.remaining(at: date) ?? 3600
                        let d = max(0, Int(rem / 86400))
                        let h = (Int(rem) % 86400) / 3600
                        let m = (Int(rem) % 3600) / 60
                        Text(rem > 0 ? "\(d)天 \(h):\(String(format: "%02d", m))" : "已到达")
                            .font(AppType.timer(26))
                            .monospacedDigit()
                            .foregroundStyle(accent)
                        if let targetDate = item?.targetDate {
                            Text("目标：\(beijingDateString(targetDate, dateStyle: .long, timeStyle: .shortened))")
                                .font(AppType.caption())
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Divider().opacity(0.3)

                Text("大号组件支持显示更多历史趋势与专注分布。")
                    .font(AppType.caption())
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(width: 330, height: 220)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
        }
    }
}

private struct WidgetGuideStep: View {
    let number: Int
    let title: String
    let detail: String
    let accent: Color

    var body: some View {
        HStack(alignment: .top, spacing: Space.m) {
            Text("\(number)")
                .font(AppType.ui(Typo.caption, .bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(accent, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(AppType.ui(Typo.body, .semibold))
                Text(detail)
                    .font(AppType.ui(Typo.footnote))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct WidgetTypeTile: View {
    let title: String
    let icon: String
    let accent: Color

    var body: some View {
        HStack(spacing: Space.s) {
            Image(systemName: icon)
                .font(AppType.caption(12, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 24, height: 24)
                .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(title)
                .font(AppType.ui(Typo.footnote, .medium))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, 10)
        .nestedSurface()
        .accessibilityElement(children: .combine)
    }
}

struct CountdownHero: View {
    let item: CountdownItem
    let accent: Color
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    var body: some View {
        let remaining = item.remaining(at: Date())
        if item.isPaused || remaining <= 0 {
            // 已暂停或已完成的目标不会再变化，不需要保留秒级时间线。
            card(remaining: remaining)
        } else {
            // 远期目标的卡片仍显示天/小时/分钟，没必要每秒重排整张卡。
            // 临近目标时恢复秒级，保留最后阶段的精确反馈并降低长期运行负荷。
            let refreshInterval: TimeInterval = remaining <= 12 * 60 * 60 ? 1 : 60
            TimelineView(.periodic(from: .now, by: refreshInterval)) { context in
                card(remaining: item.remaining(at: context.date))
            }
        }
    }

    private func card(remaining: TimeInterval) -> some View {
        let isDone = remaining <= 0
        let percent = Int((progressValue(remaining) * 100).rounded())
        let total = max(0, Int(ceil(remaining)))
        let days = total / 86400

        return VStack(spacing: Space.l) {
            if isDone {
                VStack(spacing: Space.s) {
                    Image(systemName: "flag.checkered.circle.fill")
                        .font(AppType.ui(38))
                        .foregroundStyle(BrandPalette.success)
                    Text("目标达成")
                        .font(AppType.title(Typo.sheetTitle))
                    Text("已于 \(beijingDateString(item.targetDate, dateStyle: .long, timeStyle: .shortened)) 到达")
                        .font(AppType.caption())
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("距离目标还有")
                    .font(AppType.ui(Typo.body, .medium))
                    .foregroundStyle(.secondary)

                if days > 0 {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(days)")
                            .font(.system(size: 100, weight: .light, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.3)
                        Text("天")
                            .font(AppType.ui(20))
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                    Text("\((total % 86400) / 3600) 小时 \((total % 3600) / 60) 分")
                        .font(AppType.ui(Typo.headline))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                } else {
                    Text(countdownReadout(remaining))
                        .font(AppType.timer(64))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.3)
                }
                TimeSlotProgressBar(
                    progress: progressValue(remaining), color: accent,
                    height: 5, showsKnob: true, animatesProgress: false
                )
                .padding(.top, 20)
                .frame(maxWidth: 360)
            }

            if !isDone {
                HStack {
                    Text("进度 \(percent)%")
                        .font(AppType.caption(12, weight: .semibold))
                        .foregroundStyle(accent)
                    Spacer()
                    Text("总周期 \(formattedTotalDays)")
                        .font(AppType.caption(12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: 360)
            }

        }
        .frame(maxWidth: .infinity, minHeight: 330, alignment: .center)
        .padding(.horizontal, Space.xl)
        .overlay {
            ConfettiEffectView(isActive: isDone)
        }
    }

    private func countdownReadout(_ remaining: TimeInterval) -> String {
        let total = max(0, Int(ceil(remaining)))
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if days > 0 {
            return String(format: "%d天 %02d:%02d", days, hours, minutes)
        }
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private var formattedTotalDays: String {
        let days = Int(ceil(item.totalDuration / 86400))
        return "\(max(1, days)) 天"
    }

    private func progressValue(_ remaining: TimeInterval) -> CGFloat {
        let span = max(item.totalDuration, 1)
        return remaining <= 0 ? 1 : min(1, max(0, 1 - remaining / span))
    }
}


/// 倒计时时间轴卡片：展示从创建时间到目标日期的全生命周期
struct QuickActionButton: View {
    let title: String
    let icon: String
    let tint: Color
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(AppType.ui(Typo.footnote, .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .foregroundStyle(.primary.opacity(0.78))
                .background(
                    Capsule()
                        .fill(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.045))
                        .overlay(Capsule().stroke(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.55), lineWidth: 1))
                )
        }
        .buttonStyle(TimeSlotPressableStyle())
        .accessibilityIdentifier("timeslot.quick-action.\(title)")
    }
}

struct InfoCell: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: Space.s) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(label)
                    .font(AppType.caption())
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(AppType.ui(Typo.footnote, .medium))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.l)
    }
}

struct CountdownEditor: View {
    enum Mode {
        case add
        case edit(CountdownItem)
    }

    private enum QuickTarget: String, CaseIterable, Identifiable {
        case oneHour
        case tomorrow
        case thisWeekend
        case oneWeek
        case oneMonth
        case hundredDays

        var id: String { rawValue }

        var title: String {
            switch self {
            case .oneHour: return "1 小时后"
            case .tomorrow: return "明天此时"
            case .thisWeekend: return "本周末"
            case .oneWeek: return "7 天后"
            case .oneMonth: return "30 天后"
            case .hundredDays: return "100 天"
            }
        }

        func date(from now: Date) -> Date {
            switch self {
            case .oneHour:
                return beijingCalendar.date(byAdding: .hour, value: 1, to: now)
                    ?? now.addingTimeInterval(3_600)
            case .tomorrow:
                return beijingCalendar.date(byAdding: .day, value: 1, to: now)
                    ?? now.addingTimeInterval(86_400)
            case .thisWeekend:
                let weekday = beijingCalendar.component(.weekday, from: now)
                let daysToSunday = (8 - weekday) % 7
                let target = beijingCalendar.date(byAdding: .day, value: daysToSunday == 0 ? 7 : daysToSunday, to: now) ?? now
                return beijingCalendar.date(bySettingHour: 23, minute: 59, second: 0, of: target) ?? now.addingTimeInterval(86_400 * 2)
            case .oneWeek:
                return beijingCalendar.date(byAdding: .day, value: 7, to: now)
                    ?? now.addingTimeInterval(7 * 86_400)
            case .oneMonth:
                return beijingCalendar.date(byAdding: .day, value: 30, to: now)
                    ?? now.addingTimeInterval(30 * 86_400)
            case .hundredDays:
                return beijingCalendar.date(byAdding: .day, value: 100, to: now)
                    ?? now.addingTimeInterval(100 * 86_400)
            }
        }
    }

    let mode: Mode
    let onSave: (String, Date, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var title: String
    @State private var targetDate: Date
    @State private var colorHex: String
    @FocusState private var titleFocused: Bool

    private let colorOptions: [(name: String, hex: String)] = [
        ("青绿", "#55A99C"),
        ("珊瑚", "#C07862"),
        ("金色", "#C7A35A"),
        ("苔绿", "#879C87"),
        ("紫灰", "#8B83A6"),
        ("玫瑰灰", "#B47D89")
    ]

    init(mode: Mode, onSave: @escaping (String, Date, String) -> Void) {
        self.mode = mode
        self.onSave = onSave
        switch mode {
        case .add:
            _title = State(initialValue: "")
            _targetDate = State(initialValue: beijingCalendar.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3600))
            _colorHex = State(initialValue: "#55A99C")
        case .edit(let item):
            _title = State(initialValue: item.title)
            _targetDate = State(initialValue: item.targetDate)
            _colorHex = State(initialValue: item.colorHex)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.m) {
                BrandMark(size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(modeTitle)
                        .font(AppType.title(Typo.sheetTitle))
                        .tracking(Tracking.heading)
                    Text("把一个重要时刻放进时间轴")
                        .font(AppType.caption())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("取消")
                .help("取消")
                .keyboardShortcut(.cancelAction)
            }
            .padding(Space.xl)

            Divider()

            VStack(alignment: .leading, spacing: Space.xl) {
                VStack(alignment: .leading, spacing: Space.s) {
                    HStack {
                        Text("标题")
                            .font(AppType.ui(Typo.footnote, .medium))
                        Spacer()
                        Text("\(title.count)/80")
                            .font(AppType.caption())
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                    }
                    TextField("例如：考研初试、项目演示、旅行出发", text: $title)
                        .textFieldStyle(.roundedBorder)
                        .focused($titleFocused)
                    Text("名称会显示在侧栏和桌面小组件中")
                        .font(AppType.caption())
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: Space.m) {
                    Text("目标时间")
                        .font(AppType.ui(Typo.footnote, .medium))

                    DatePicker(
                        "日期与时间",
                        selection: $targetDate,
                        in: minimumDate...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.field)

                    HStack(spacing: 6) {
                        ForEach(QuickTarget.allCases) { target in
                            Button(target.title) {
                                targetDate = target.date(from: Date())
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }

                    if isTargetInvalid {
                        Label("目标时间需要晚于现在", systemImage: "exclamationmark.triangle.fill")
                            .font(AppType.caption(weight: .medium))
                            .foregroundStyle(.orange)
                    }
                }

                VStack(alignment: .leading, spacing: Space.m) {
                    Text("识别色")
                        .font(AppType.ui(Typo.footnote, .medium))
                    HStack(spacing: Space.l) {
                        ForEach(colorOptions, id: \.hex) { option in
                            Button {
                                colorHex = option.hex
                            } label: {
                                VStack(spacing: 6) {
                                    Circle()
                                        .fill(DataSignal.color(hex: option.hex))
                                        .frame(width: 28, height: 28)
                                        .overlay {
                                            Circle()
                                                .stroke(
                                                    Color.primary.opacity(isColorSelected(option) ? 0.82 : 0.08),
                                                    lineWidth: isColorSelected(option) ? 2 : 1
                                                )
                                                .padding(isColorSelected(option) ? -4 : 0)
                                        }
                                        .overlay {
                                            if isColorSelected(option) {
                                                Image(systemName: "checkmark")
                                                    .font(AppType.caption(11, weight: .bold))
                                                    .foregroundStyle(.white)
                                            }
                                        }
                                    Text(option.name)
                                        .font(AppType.caption())
                                        .foregroundStyle(.secondary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(TimeSlotPressableStyle())
                            .accessibilityLabel(option.name)
                            .accessibilityValue(isColorSelected(option) ? "已选中" : "未选中")
                        }
                    }
                }

                // 实时预览卡片
                HStack(spacing: Space.m) {
                    Circle()
                        .fill(DataSignal.color(hex: colorHex))
                        .frame(width: 10, height: 10)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(normalizedTitle.isEmpty ? "倒计时预览" : normalizedTitle)
                            .font(AppType.ui(Typo.body, .medium))
                            .lineLimit(1)
                        Text(beijingDateString(targetDate, dateStyle: .long, timeStyle: .shortened))
                            .font(AppType.caption())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "rectangle.3.group")
                        .foregroundStyle(DataSignal.color(hex: colorHex))
                }
                .padding(Space.m)
                .nestedSurface()
            }
            .padding(Space.xl)

            Divider()

            HStack {
                Text(isEditing ? "修改会立即同步到小组件" : "保存后可随时编辑或暂停")
                    .font(AppType.caption())
                    .foregroundStyle(.secondary)
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isEditing ? "保存修改" : "创建倒计时") { save() }
                    .buttonStyle(.borderedProminent)
                    .tint(DataSignal.color(hex: colorHex))
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding(Space.xl)
        }
        .frame(width: 530)
        .onAppear { titleFocused = true }
        .onChange(of: title) { _, newValue in
            if newValue.count > 80 {
                title = String(newValue.prefix(80))
            }
        }
    }

    private var normalizedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var minimumDate: Date {
        isEditing ? min(Date(), targetDate) : Date()
    }

    private var isTargetInvalid: Bool {
        !isEditing && targetDate <= Date()
    }

    private var canSave: Bool {
        !normalizedTitle.isEmpty && !isTargetInvalid
    }

    private func save() {
        guard canSave else { return }
        onSave(normalizedTitle, targetDate, colorHex)
        dismiss()
    }

    private func isColorSelected(_ option: (name: String, hex: String)) -> Bool {
        ColorHex.normalized(colorHex).caseInsensitiveCompare(option.hex) == .orderedSame
            || DataSignal.presentationHex(for: colorHex).caseInsensitiveCompare(option.hex) == .orderedSame
    }

    private var modeTitle: String {
        switch mode {
        case .add: return "新建倒计时"
        case .edit: return "编辑倒计时"
        }
    }
}

private final class TimelineInteractionState {
    var hoverPoint = CGPoint.zero
}

private struct HomeHourTimeline: View {
    @ObservedObject var store: CountdownStore
    let currentDate: Date
    let onOpenFocus: () -> Void
    var onEditRecordIDs: ([UUID]) -> Void = { _ in }
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var pan = CGSize.zero
    @State private var scaleX: CGFloat = 1
    @State private var scaleY: CGFloat = 1.35
    @GestureState private var drag = CGSize.zero
    @State private var hovering = false
    // 指针位置只供缩放手势使用，不发布为 SwiftUI 状态，避免连续 hover 触发整张时间轴重绘。
    @State private var interactionState = TimelineInteractionState()
    @State private var scrollMonitor: Any?
    @State private var lastPlotWidth: CGFloat = 0
    @State private var lastPlotHeight: CGFloat = 0
    @State private var lastWorldWidth: CGFloat = 0
    @State private var lastWorldHeight: CGFloat = 0
    @State private var lastDayCount = 7
    // 视口拖动时只改变位移，不再反复扫描最多一万条历史记录。
    // 快照仅在历史、任务、计时状态、分钟时钟或配色变化时更新。
    @State private var cachedDays: [Date] = []
    @State private var cachedBlocks: [TimelineBlock] = []

    private let hourGutter: CGFloat = 44
    private let headerHeight: CGFloat = 44
    private let fillDayCount: CGFloat = 7
    private let defaultScaleY: CGFloat = 1.35

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("时间轴")
                    .font(AppType.title(Typo.headline))
                Spacer()
                timelineLegend
                Button("回到今天") {
                    resetViewport()
                }
                .font(AppType.caption(11, weight: .medium))
                .foregroundStyle(.secondary)
                .buttonStyle(TimeSlotPressableStyle())
            }

            GeometryReader { geo in
                let days = cachedDays.isEmpty ? timelineDays(at: currentDate) : cachedDays
                let livePan = CGSize(width: pan.width + drag.width, height: pan.height + drag.height)
                let plotWidth = max(1, geo.size.width - hourGutter)
                let scrubberHeight: CGFloat = 22
                let plotHeight = max(1, geo.size.height - headerHeight - scrubberHeight)
                let fillWidth = plotWidth / fillDayCount
                let fitWidth = plotWidth / CGFloat(max(days.count, 1))
                let dayWidth = max(fitWidth, fillWidth * scaleX)
                let hourHeight = (plotHeight / 24) * scaleY
                let hourStep: Int = {
                    if hourHeight < 9 { return 12 }
                    if hourHeight < 13 { return 6 }
                    if hourHeight < 20 { return 3 }
                    return 1
                }()
                let worldWidth = CGFloat(days.count) * dayWidth
                let worldHeight = 24 * hourHeight
                let clamped = clampPan(livePan, plotWidth: plotWidth, plotHeight: plotHeight, worldWidth: worldWidth, worldHeight: worldHeight)
                let blocks = cachedDays.isEmpty ? timelineBlocks(days: days, at: currentDate) : cachedBlocks

                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Color.clear.frame(width: hourGutter, height: headerHeight)
                        dayHeader(days: days, dayWidth: dayWidth)
                            .frame(width: plotWidth, height: headerHeight, alignment: .leading)
                            .offset(x: clamped.width)
                            .clipped()
                    }
                    HStack(spacing: 0) {
                        hourGutterView(hourHeight: hourHeight, hourStep: hourStep)
                            .frame(width: hourGutter, height: plotHeight, alignment: .top)
                            .offset(y: clamped.height)
                            .clipped()

                        ZStack(alignment: .topLeading) {
                            timelinePlot(days: days, dayWidth: dayWidth, hourHeight: hourHeight, hourStep: hourStep)
                            ForEach(blocks) { block in
                                timelineBlockView(block, dayWidth: dayWidth, hourHeight: hourHeight)
                            }
                            // 当前时间线单独按分钟更新，不再带着历史任务块和整个看板一起重算。
                            TimelineView(.periodic(from: .now, by: 60)) { context in
                                nowLine(days: days, dayWidth: dayWidth, hourHeight: hourHeight, date: context.date)
                            }
                        }
                        .frame(width: worldWidth, height: worldHeight, alignment: .topLeading)
                        .offset(clamped)
                        .frame(width: plotWidth, height: plotHeight, alignment: .topLeading)
                        .clipped()
                        .contentShape(Rectangle())
                        .gesture(panGesture)
                    }

                    HStack(spacing: 0) {
                        Color.clear.frame(width: hourGutter, height: scrubberHeight)
                        panScrubber(
                            days: days,
                            plotWidth: plotWidth,
                            worldWidth: worldWidth,
                            clampedX: clamped.width
                        )
                        .frame(width: plotWidth, height: scrubberHeight)
                    }
                }
                .onAppear {
                    pan = CGSize(
                        width: min(0, plotWidth - worldWidth),
                        height: min(0, max(plotHeight - worldHeight, -8 * hourHeight))
                    )
                    lastPlotWidth = plotWidth
                    lastPlotHeight = plotHeight
                    lastWorldWidth = worldWidth
                    lastWorldHeight = worldHeight
                    lastDayCount = days.count
                    refreshTimelineSnapshot(at: currentDate)
                    installScrollMonitor()
                }
                .onChange(of: worldWidth) { _, newWidth in
                    lastWorldWidth = newWidth
                    lastPlotWidth = plotWidth
                    lastDayCount = days.count
                    pan = clampedPan(pan)
                }
                .onChange(of: worldHeight) { _, newHeight in
                    lastWorldHeight = newHeight
                    lastPlotHeight = plotHeight
                    pan = clampedPan(pan)
                }
                .onChange(of: geo.size) { _, _ in
                    lastPlotWidth = plotWidth
                    lastPlotHeight = plotHeight
                    lastWorldWidth = worldWidth
                    lastWorldHeight = worldHeight
                    pan = clampedPan(pan)
                }
                .onDisappear { removeScrollMonitor() }
            }
            .frame(minHeight: 280)
            .onHover { hovering = $0 }
            .onContinuousHover { phase in
                if case .active(let point) = phase {
                    interactionState.hoverPoint = CGPoint(x: point.x - hourGutter, y: point.y - headerHeight)
                }
            }
        }
        .onChange(of: currentDate) { _, date in refreshTimelineSnapshot(at: date) }
        .onChange(of: store.pomodoroHistory) { _, _ in refreshTimelineSnapshot(at: currentDate) }
        .onChange(of: store.pomodoroTasks) { _, _ in refreshTimelineSnapshot(at: currentDate) }
        .onChange(of: store.pomodoro) { _, _ in refreshTimelineSnapshot(at: currentDate) }
        .onChange(of: colorScheme) { _, _ in refreshTimelineSnapshot(at: currentDate) }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 340, alignment: .topLeading)
        .background(alignment: .topTrailing) {
            Circle()
                .fill(store.accentPreset.color.opacity(colorScheme == .dark ? 0.08 : 0.07))
                .frame(width: 300, height: 300)
                .blur(radius: 70)
                .offset(x: 70, y: -70)
                .allowsHitTesting(false)
        }
        .glassBoard(wash: store.accentPreset.color)
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .updating($drag) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                pan = clampedPan(
                    CGSize(
                        width: pan.width + value.translation.width,
                        height: pan.height + value.translation.height
                    )
                )
            }
    }

    private func zoom(
        fromScaleX: CGFloat,
        fromScaleY: CGFloat,
        fromPan: CGSize,
        factorX: CGFloat,
        factorY: CGFloat,
        around focal: CGPoint,
        dayCount: Int = 7
    ) {
        // 水平缩小到「刚好填满视口」的初始倍率为止，垂直缩小到 24 小时填满为止，
        // 任何方向缩放都不会在底部或右侧留下空白。
        let minX = minScaleX(for: dayCount)
        let nextX = min(2.8, max(minX, fromScaleX * factorX))
        let nextY = min(3.0, max(1.0, fromScaleY * factorY))
        let count = CGFloat(max(dayCount, 1))
        let worldWidthAtScale: (CGFloat) -> CGFloat = { scale in
            count * max(lastPlotWidth / count, (lastPlotWidth / fillDayCount) * scale)
        }
        let fromWorldWidth = worldWidthAtScale(fromScaleX)
        let nextWorldWidth = worldWidthAtScale(nextX)
        let widthFactor = nextWorldWidth / max(fromWorldWidth, 0.001)
        let heightFactor = nextY / max(fromScaleY, 0.001)
        let focalPoint = CGPoint(
            x: min(lastPlotWidth, max(0, focal.x)),
            y: min(lastPlotHeight, max(0, focal.y))
        )
        scaleX = nextX
        scaleY = nextY
        let proposed = CGSize(
            width: focalPoint.x - (focalPoint.x - fromPan.width) * widthFactor,
            height: focalPoint.y - (focalPoint.y - fromPan.height) * heightFactor
        )
        pan = clampPan(
            proposed,
            plotWidth: lastPlotWidth,
            plotHeight: lastPlotHeight,
            worldWidth: nextWorldWidth,
            worldHeight: lastPlotHeight * nextY
        )
    }

    private func clampPan(_ value: CGSize, plotWidth: CGFloat, plotHeight: CGFloat, worldWidth: CGFloat, worldHeight: CGFloat) -> CGSize {
        let minX = min(0, plotWidth - worldWidth)
        let minY = min(0, plotHeight - worldHeight)
        return CGSize(
            width: min(0, max(minX, value.width)),
            height: min(0, max(minY, value.height))
        )
    }

    private func clampedPan(_ value: CGSize) -> CGSize {
        clampPan(
            value,
            plotWidth: lastPlotWidth,
            plotHeight: lastPlotHeight,
            worldWidth: lastWorldWidth,
            worldHeight: lastWorldHeight
        )
    }

    private var timelineLegend: some View {
        let titles = Array(Set(cachedBlocks.map(\.title))).sorted()
        return HStack(spacing: 8) {
            ForEach(titles.prefix(5), id: \.self) { title in
                HStack(spacing: 4) {
                    Circle()
                        .fill(cachedBlocks.first { $0.title == title }?.color ?? Color.secondary)
                        .frame(width: 6, height: 6)
                    Text(title)
                        .font(AppType.caption(11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityHidden(titles.isEmpty)
    }

    private func resetViewport() {
        let count = CGFloat(max(lastDayCount, 1))
        let dayWidth = max(lastPlotWidth / count, (lastPlotWidth / fillDayCount))
        let resetWorldWidth = count * dayWidth
        let resetWorldHeight = lastPlotHeight * defaultScaleY
        let target = CGSize(
            width: min(0, lastPlotWidth - resetWorldWidth),
            height: min(0, max(lastPlotHeight - resetWorldHeight, -8 * (resetWorldHeight / 24)))
        )
        let changes = {
            scaleX = 1
            scaleY = defaultScaleY
            pan = target
        }
        if reduceMotion {
            changes()
        } else {
            withAnimation(.spring(response: 0.34, dampingFraction: 1)) {
                changes()
            }
        }
    }

    private func refreshTimelineSnapshot(at date: Date) {
        let days = timelineDays(at: date)
        let blocks = timelineBlocks(days: days, at: date)
        cachedDays = days
        cachedBlocks = blocks
        lastDayCount = days.count
    }

    private func panScrubber(days: [Date], plotWidth: CGFloat, worldWidth: CGFloat, clampedX: CGFloat) -> some View {
        let travel = max(1, worldWidth - plotWidth)
        let visibleRatio = min(1, plotWidth / max(worldWidth, 1))
        let progress = min(1, max(0, -clampedX / travel))

        return GeometryReader { geo in
            let trackWidth = geo.size.width
            let thumbWidth = max(22, trackWidth * visibleRatio)
            let maxOffset = max(0, trackWidth - thumbWidth)
            let thumbX = maxOffset * progress

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.07))
                    .frame(height: 2)

                Capsule()
                    .fill(Color.primary.opacity(0.34))
                    .frame(width: thumbWidth, height: 3)
                    .offset(x: thumbX)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let x = min(maxOffset, max(0, value.location.x - thumbWidth / 2))
                        let next = maxOffset == 0 ? 1 : x / maxOffset
                        pan.width = -next * travel
                    }
            )
            .help(scrubberHelp(days: days, progress: progress, visibleRatio: visibleRatio))
        }
    }

    private func scrubberHelp(days: [Date], progress: CGFloat, visibleRatio: CGFloat) -> String {
        guard !days.isEmpty else { return "日期范围" }
        let startIndex = Int((CGFloat(days.count - 1) * progress).rounded())
        let endIndex = min(days.count - 1, startIndex + max(0, Int((CGFloat(days.count) * visibleRatio).rounded()) - 1))
        let start = days[min(max(startIndex, 0), days.count - 1)]
        let end = days[endIndex]
        let formatter = DateFormatter()
        formatter.locale = beijingLocale
        formatter.timeZone = beijingTimeZone
        formatter.dateFormat = "M月d日"
        return "\(formatter.string(from: start)) - \(formatter.string(from: end)) · 共 \(days.count) 天"
    }

    private func dayHeader(days: [Date], dayWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(days, id: \.self) { day in
                let isToday = beijingCalendar.isDateInToday(day)
                VStack(spacing: 2) {
                    Text(weekdayLabel(day))
                        .font(AppType.caption(11, weight: .medium))
                        .foregroundStyle(Color.secondary.opacity(0.82))
                    Text("\(beijingCalendar.component(.day, from: day))")
                        .font(.system(size: 14, weight: isToday ? .semibold : .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(isToday ? store.accentPreset.color : Color.primary.opacity(0.70))
                }
                .frame(width: dayWidth, height: headerHeight)
            }
        }
    }

    private func hourGutterView(hourHeight: CGFloat, hourStep: Int) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                Text(hour % hourStep == 0 ? String(format: "%02d:00", hour) : "")
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.secondary.opacity(0.78))
                    .frame(width: hourGutter - 8, height: hourHeight, alignment: .topTrailing)
            }
        }
        .padding(.trailing, 8)
    }

    private func timelinePlot(days: [Date], dayWidth: CGFloat, hourHeight: CGFloat, hourStep: Int) -> some View {
        Canvas { context, size in
            for hour in 0...24 {
                guard hour % hourStep == 0 else { continue }
                let y = CGFloat(hour) * hourHeight
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(line, with: .color(Color.primary.opacity(hour % 6 == 0 ? 0.08 : 0.035)), lineWidth: 1)
            }
            for (index, day) in days.enumerated() {
                let x = CGFloat(index) * dayWidth
                var line = Path()
                line.move(to: CGPoint(x: x, y: 0))
                line.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(line, with: .color(Color.primary.opacity(homeIsWeekend(day) ? 0.05 : 0.03)), lineWidth: 1)
                if homeIsWeekend(day) {
                    context.fill(
                        Path(CGRect(x: x, y: 0, width: dayWidth, height: size.height)),
                        with: .color(Color.primary.opacity(0.025))
                    )
                }
            }
        }
    }

    private func timelineBlockView(_ block: TimelineBlock, dayWidth: CGFloat, hourHeight: CGFloat) -> some View {
        let laneWidth = (dayWidth - 8) / CGFloat(max(block.laneCount, 1))
        let x = CGFloat(block.dayIndex) * dayWidth + 4 + laneWidth * CGFloat(block.lane)
        let y = CGFloat(block.startHour) * hourHeight + 1
        let height = max(6, CGFloat(block.durationHours) * hourHeight - 2)
        // 专注越长块越深，形成可读的热力层次。
        let intensity: Double
        switch block.durationHours {
        case 1.5...: intensity = 0.72
        case 0.75..<1.5: intensity = 0.52
        case 0.3..<0.75: intensity = 0.38
        default: intensity = 0.26
        }
        return Button {
            if block.live {
                onOpenFocus()
            } else {
                onEditRecordIDs(block.recordIDs)
            }
        } label: {
            Group {
                if height > 24 && laneWidth > 46 {
                    Text(block.title)
                        .font(AppType.caption(11, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(Color.primary.opacity(0.82))
                        .padding(.horizontal, 6)
                        .padding(.top, 4)
                        .frame(width: laneWidth - 2, height: height, alignment: .topLeading)
                } else {
                    Color.clear.frame(width: laneWidth - 2, height: height)
                }
            }
            .background {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                block.color.opacity(min(1, intensity + 0.16)),
                                block.color.opacity(intensity)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(block.color.opacity(0.35), lineWidth: 0.5)
                    }
            }
            .shadow(color: block.color.opacity(0.22), radius: 3, y: 1)
            .help("\(block.title)  \(block.timeLabel)\(block.live ? " · 进行中" : " · 点按修正")")
        }
        .buttonStyle(TimeSlotPressableStyle())
        .accessibilityLabel("\(block.title)，\(block.timeLabel)\(block.live ? "，进行中" : "")")
        .contextMenu {
            if block.live {
                Text("进行中的计时请先停止")
            } else {
                Button("删除这条记录", role: .destructive) {
                    store.deletePomodoroHistory(ids: block.recordIDs, title: block.title)
                }
            }
        }
        .offset(x: x, y: y)
    }

    private func nowLine(days: [Date], dayWidth: CGFloat, hourHeight: CGFloat, date: Date) -> some View {
        let now = date
        guard let todayIndex = days.firstIndex(where: { beijingCalendar.isDate($0, inSameDayAs: now) }) else {
            return AnyView(EmptyView())
        }
        let minutes = beijingCalendar.component(.hour, from: now) * 60
            + beijingCalendar.component(.minute, from: now)
        let y = CGFloat(minutes) / 60 * hourHeight
        let accent = store.accentPreset.color
        return AnyView(
            Rectangle()
                .fill(accent.opacity(0.85))
                .frame(width: dayWidth - 8, height: 2)
                .shadow(color: accent.opacity(0.45), radius: 3)
                .offset(x: CGFloat(todayIndex) * dayWidth + 4, y: y)
        )
    }

    private func installScrollMonitor() {
        removeScrollMonitor()
        // AppKit 是这里唯一的捏合事件源。SwiftUI 的 MagnificationGesture 在嵌套的
        // 自定义拖动层里会漏掉 macOS 捏合事件；只保留一个 AppKit 入口也不会重复缩放。
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify]) { event in
            guard hovering else { return event }
            if event.type == .magnify {
                let factor = max(0.5, 1 + event.magnification)
                zoom(
                    fromScaleX: scaleX,
                    fromScaleY: scaleY,
                    fromPan: pan,
                    factorX: factor,
                    factorY: factor,
                    around: interactionState.hoverPoint,
                    dayCount: lastDayCount
                )
                return nil
            }
            if event.modifierFlags.contains(.command) {
                // ⌘+滚轮：水平缩放；加 Shift 只缩放垂直。
                let factor = CGFloat(pow(1.01, Double(event.scrollingDeltaY)))
                zoom(
                    fromScaleX: scaleX,
                    fromScaleY: scaleY,
                    fromPan: pan,
                    factorX: event.modifierFlags.contains(.shift) ? 1 : factor,
                    factorY: event.modifierFlags.contains(.shift) ? factor : 1,
                    around: interactionState.hoverPoint,
                    dayCount: lastDayCount
                )
                return nil
            }

            // 与 macOS 的系统习惯一致：普通双指滚动只平移，捏合才缩放。
            // momentumPhase 产生的后续事件会自然形成惯性；到达边缘后把事件交还外层页面。
            let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 12
            let horizontalDelta = event.modifierFlags.contains(.shift) && event.scrollingDeltaX == 0
                ? event.scrollingDeltaY
                : event.scrollingDeltaX
            let proposed = CGSize(
                width: pan.width + horizontalDelta * multiplier,
                height: pan.height + (event.modifierFlags.contains(.shift) ? 0 : event.scrollingDeltaY * multiplier)
            )
            let next = clampedPan(proposed)
            let moved = abs(next.width - pan.width) > 0.01 || abs(next.height - pan.height) > 0.01
            if moved {
                pan = next
                return nil
            }
            return event
        }
    }

    private func removeScrollMonitor() {
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
            self.scrollMonitor = nil
        }
    }

    private func minScaleX(for dayCount: Int) -> CGFloat {
        min(1, fillDayCount / CGFloat(max(dayCount, 1)))
    }

    private func timelineDays(at date: Date = Date()) -> [Date] {
        let today = beijingCalendar.startOfDay(for: date)
        var starts = store.pomodoroHistory
            .filter { ($0.phase == .focus || $0.status == .stopwatch) && $0.actualDuration > 0 }
            .map { beijingCalendar.startOfDay(for: $0.startedAt) }
        if store.pomodoro.isStopwatchActive {
            let elapsed = store.pomodoro.stopwatchElapsed(at: date)
            let liveStart = store.pomodoro.stopwatchSessionStartedAt ?? date.addingTimeInterval(-elapsed)
            starts.append(beijingCalendar.startOfDay(for: liveStart))
        }
        let oldest = starts.min() ?? (beijingCalendar.date(byAdding: .day, value: -6, to: today) ?? today)
        let capped = beijingCalendar.date(byAdding: .day, value: -179, to: today) ?? today
        let start = max(oldest, capped)
        var days: [Date] = []
        var cursor = start
        while cursor <= today {
            days.append(cursor)
            guard let next = beijingCalendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return days
    }

    private func timelineBlocks(days: [Date], at date: Date = Date()) -> [TimelineBlock] {
        guard let first = days.first, let last = days.last else { return [] }
        let windowStart = first
        let windowEnd = last.addingTimeInterval(86_400)
        var blocks: [TimelineBlock] = []

        func appendSpan(title: String, start: Date, end: Date, live: Bool, ids: [UUID]) {
            var cursor = max(start, windowStart)
            let finish = min(end, windowEnd)
            guard finish > cursor else { return }
            let colorHex = store.pomodoroTasks.first {
                PomodoroTaskPalette.normalized($0.title) == title
            }?.colorHex
            let color = DataSignal.color(
                hex: colorHex?.isEmpty == false
                    ? colorHex!
                    : PomodoroTaskPalette.fallbackColorHex(for: title)
            )
            while cursor < finish {
                let day = beijingCalendar.startOfDay(for: cursor)
                let nextDay = beijingCalendar.date(byAdding: .day, value: 1, to: day) ?? cursor.addingTimeInterval(86_400)
                let sliceEnd = min(finish, nextDay)
                if let dayIndex = days.firstIndex(of: day) {
                    let startHour = cursor.timeIntervalSince(day) / 3600
                    let durationHours = max(0.18, sliceEnd.timeIntervalSince(cursor) / 3600)
                    blocks.append(
                        TimelineBlock(
                            id: TimelineBlockIdentity.make(
                                recordIDs: ids,
                                day: day,
                                startHour: startHour,
                                live: live
                            ),
                            title: title,
                            color: color,
                            dayIndex: dayIndex,
                            startHour: startHour,
                            durationHours: durationHours,
                            timeLabel: live ? "进行中" : hourRangeLabel(from: cursor, to: sliceEnd),
                            lane: 0,
                            laneCount: 1,
                            recordIDs: ids,
                            live: live
                        )
                    )
                }
                cursor = sliceEnd
            }
        }

        for record in store.pomodoroHistory {
            let isFocus = record.phase == .focus && record.actualDuration > 0
            let isStopwatch = record.status == .stopwatch && record.actualDuration > 0
            guard isFocus || isStopwatch else { continue }
            appendSpan(
                title: PomodoroTaskPalette.normalized(record.taskTitle),
                start: record.startedAt,
                end: record.endedAt,
                live: false,
                ids: [record.id]
            )
        }

        let state = store.pomodoro
        let liveTitle = PomodoroTaskPalette.normalized(state.taskTitle)
        if state.isStopwatchActive {
            let elapsed = state.stopwatchElapsed(at: date)
            let start = state.stopwatchSessionStartedAt ?? date.addingTimeInterval(-elapsed)
            appendSpan(title: liveTitle, start: start, end: date, live: true, ids: [])
        } else if state.isRunning, state.phase == .focus {
            let start = state.sessionStartedAt ?? state.activeStartedAt ?? date
            appendSpan(title: liveTitle, start: start, end: date, live: true, ids: [])
        }
        return packedLanes(blocks)
    }

    private func packedLanes(_ blocks: [TimelineBlock]) -> [TimelineBlock] {
        var grouped: [Int: [TimelineBlock]] = [:]
        for block in blocks {
            grouped[block.dayIndex, default: []].append(block)
        }
        var result: [TimelineBlock] = []
        for dayBlocks in grouped.values {
            let sorted = dayBlocks.sorted { $0.startHour < $1.startHour }
            var laneEnds: [Double] = []
            var placed: [(block: TimelineBlock, lane: Int)] = []
            for block in sorted {
                let lane = laneEnds.firstIndex { $0 <= block.startHour + 0.02 } ?? laneEnds.count
                if lane == laneEnds.count {
                    laneEnds.append(block.startHour + block.durationHours)
                } else {
                    laneEnds[lane] = block.startHour + block.durationHours
                }
                placed.append((block, lane))
            }
            let laneCount = max(1, laneEnds.count)
            result.append(contentsOf: placed.map { item in
                var next = item.block
                next.lane = item.lane
                next.laneCount = laneCount
                return next
            })
        }
        return result
    }

    private func weekdayLabel(_ date: Date) -> String {
        let names = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        return names[beijingCalendar.component(.weekday, from: date) - 1]
    }

    private func hourRangeLabel(from start: Date, to end: Date) -> String {
        let startHour = beijingCalendar.component(.hour, from: start)
        let startMinute = beijingCalendar.component(.minute, from: start)
        let endHour = beijingCalendar.component(.hour, from: end)
        let endMinute = beijingCalendar.component(.minute, from: end)
        return String(format: "%d:%02d-%d:%02d", startHour, startMinute, endHour, endMinute)
    }

    private func homeIsWeekend(_ date: Date) -> Bool {
        [1, 7].contains(beijingCalendar.component(.weekday, from: date))
    }
}

private struct TimelineBlock: Identifiable {
    let id: String
    let title: String
    let color: Color
    let dayIndex: Int
    let startHour: Double
    let durationHours: Double
    let timeLabel: String
    var lane: Int
    var laneCount: Int
    let recordIDs: [UUID]
    let live: Bool
}
