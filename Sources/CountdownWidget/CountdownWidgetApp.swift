import AppKit
import SwiftUI
import Combine
import WidgetKit
import Charts

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


enum CountdownFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case active = "进行中"
    case paused = "已暂停"
    case completed = "已到达"

    var id: String { rawValue }
}

enum CountdownViewMode: String, CaseIterable, Identifiable {
    case card = "卡片详情"
    case roadmap = "时间流全景"

    var id: String { rawValue }
}

struct ContentView: View {
    @ObservedObject var store: CountdownStore
    @State private var showingAdd = false
    @State private var showingEdit = false
    @State private var showingWidgetHelp = false
    @State private var showingShortcuts = false
    @State private var pendingDelete: CountdownItem?
    @State private var searchText = ""
    @State private var countdownFilter: CountdownFilter = .all
    @State private var countdownViewMode: CountdownViewMode = .card
    @State private var selectedSection: TimeBookSection = .home
    @State private var hoveredRail: TimeBookSection?
    @FocusState private var searchFieldFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private var accent: Color { store.accentPreset.color }
    private var stopwatchColor: Color { store.accentPreset.color }

    var filteredItems: [CountdownItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date()
        return store.items.filter { item in
            if !query.isEmpty && !item.title.localizedCaseInsensitiveContains(query) {
                return false
            }
            switch countdownFilter {
            case .all:
                return true
            case .active:
                return !item.isPaused && item.remaining(at: now) > 0
            case .paused:
                return item.isPaused
            case .completed:
                return !item.isPaused && item.remaining(at: now) <= 0
            }
        }
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
                            sidebar
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
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text("Time")
                            .font(.system(size: 26, weight: .ultraLight, design: .serif))
                        Text("Slot")
                            .font(.system(size: 26, weight: .regular, design: .serif))
                    }
                    .tracking(-0.8)
                    Text(workspaceTitle)
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .tracking(0.9)
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

            Button {
                showingShortcuts = true
            } label: {
                Image(systemName: "keyboard")
                    .font(AppType.ui(13, .medium))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(TimeSlotPressableStyle())
            .background(circleChrome)
            .help("快捷键速查 (⌘/)")
            .accessibilityLabel("快捷键")

            Button {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                    selectedSection = .settings
                }
            } label: {
                Image(systemName: "gearshape")
                    .font(AppType.ui(13, .medium))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(TimeSlotPressableStyle())
            .background {
                if selectedSection == .settings {
                    circleChromeSelected
                } else {
                    circleChrome
                }
            }
            .foregroundStyle(Color.primary.opacity(0.72))
            .help("设置")
            .accessibilityLabel("设置")
            .accessibilityIdentifier("timeslot.settings.open")
            .accessibilityValue(selectedSection == .settings ? "已选中" : "未选中")
        }
        .padding(.leading, 8)
    }

    private var pillChrome: some View {
        Capsule()
            .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.04))
            .overlay(Capsule().stroke(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08), lineWidth: 1))
    }

    private var circleChrome: some View {
        Circle()
            .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.04))
            .overlay(Circle().stroke(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08), lineWidth: 1))
    }

    private var circleChromeSelected: some View {
        Circle()
            .fill(Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.08))
            .overlay(Circle().stroke(Color.primary.opacity(0.10), lineWidth: 1))
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
                .font(AppType.ui(12.5, .medium))
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
                    .font(AppType.ui(15, .medium))
                    .frame(width: 36, height: 36)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(TimeSlotPressableStyle())
            .help("快捷键速查 (⌘/)")
            .padding(.bottom, 22)
        }
        .frame(width: 72)
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
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(isSelected ? BrandPalette.gold : Color.clear)
                    .frame(width: 3, height: 18)

                Image(systemName: systemImage)
                    .font(AppType.ui(15, .medium))
                    .frame(width: 40, height: 40)
                    .foregroundStyle(isSelected ? Color.primary : (isHovered ? Color.primary.opacity(0.8) : Color.primary.opacity(0.42)))
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(colorScheme == .dark ? 0.14 : 0.78))
                        } else if isHovered {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.06))
                        }
                    }
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
            }
            .frame(width: 56, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(TimeSlotPressableStyle())
        .onHover { hovering in
            hoveredRail = hovering ? section : nil
        }
        .help(title)
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? "已选中" : "未选中")
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        selectedSection == .countdown
                            ? "倒计时"
                            : (selectedSection == .pomodoro ? "番茄钟" : "设置")
                    )
                        .font(AppType.pageTitle(22))
                        .tracking(-0.3)
                    Text(
                        selectedSection == .countdown
                            ? "选择一个目标"
                            : (selectedSection == .pomodoro ? "当前节奏" : "偏好与数据")
                    )
                        .font(AppType.caption())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if selectedSection == .countdown {
                    Button {
                        showingAdd = true
                    } label: {
                        Image(systemName: "plus")
                            .font(AppType.ui(14, .medium))
                            .frame(width: 32, height: 32)
                            .foregroundStyle(.primary.opacity(0.78))
                    }
                    .buttonStyle(TimeSlotPressableStyle())
                    .background(circleChrome)
                    .help("新建倒计时 (⌘N)")
                    .accessibilityLabel("新建倒计时")
                    .accessibilityIdentifier("timeslot.countdown.add")
                }
            }
            .padding(.horizontal, Space.xl)
            .padding(.top, 20)
            .padding(.bottom, 14)

            if selectedSection == .countdown {
                // 搜索框
                HStack(spacing: Space.s) {
                    Image(systemName: "magnifyingglass")
                        .font(AppType.caption(12, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField("搜索倒计时 (⌘F)", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(AppType.ui(13))
                        .focused($searchFieldFocused)
                        .accessibilityIdentifier("timeslot.countdown.search")
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            searchFieldFocused = true
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(AppType.caption(12))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("清除搜索")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.045),
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .stroke(searchFieldFocused ? accent.opacity(0.55) : Color.clear, lineWidth: 1.5)
                }
                .animation(.easeOut(duration: 0.15), value: searchFieldFocused)
                .padding(.horizontal, Space.l)
                .padding(.bottom, 10)

                HStack(spacing: 2) {
                    ForEach(CountdownFilter.allCases) { filter in
                        let isSelected = countdownFilter == filter
                        Button {
                            withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
                                countdownFilter = filter
                            }
                        } label: {
                            Text(filter.rawValue)
                                .font(AppType.caption(11.5, weight: isSelected ? .semibold : .regular))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(
                                    isSelected
                                        ? Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.08)
                                        : Color.clear,
                                    in: Capsule()
                                )
                                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                        }
                        .buttonStyle(TimeSlotPressableStyle())
                    }
                    Spacer()
                    Text("\(filteredItems.count)")
                        .font(AppType.caption(11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, Space.l)
                .padding(.bottom, 8)

                ScrollView {
                    if filteredItems.isEmpty {
                        VStack(spacing: Space.s) {
                            Image(systemName: searchText.isEmpty ? "calendar.badge.plus" : "magnifyingglass")
                                .font(AppType.ui(22, .medium))
                                .foregroundStyle(.primary.opacity(0.55))
                                .padding(.bottom, Space.xs)
                            Text(searchText.isEmpty ? "还没有倒计时" : "没有匹配结果")
                                .font(AppType.ui(Typo.footnote, .semibold))
                            Text(searchText.isEmpty ? "添加一个目标，开始记录值得等待的时刻。" : "换个关键词试试。")
                                .font(AppType.caption())
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                            if searchText.isEmpty {
                                Button {
                                    showingAdd = true
                                } label: {
                                    Text("新建倒计时")
                                        .font(AppType.ui(12.5, .medium))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .foregroundStyle(.primary.opacity(0.78))
                                }
                                .buttonStyle(TimeSlotPressableStyle())
                                .inkPill()
                                .padding(.top, Space.xs)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, Space.m)
                        .padding(.top, Space.xl)
                    } else {
                        LazyVStack(spacing: Space.xs) {
                            ForEach(filteredItems) { item in
                                CountdownRow(
                                    item: item,
                                    isSelected: item.id == store.selectedItem?.id,
                                    accent: accent
                                ) {
                                    store.selectedID = item.id
                                }
                                .accessibilityIdentifier("timeslot.countdown.row.\(item.id.uuidString)")
                                .simultaneousGesture(
                                    TapGesture(count: 2).onEnded {
                                        store.selectedID = item.id
                                        showingEdit = true
                                    }
                                )
                                .contextMenu {
                                    Button("编辑…") {
                                        store.selectedID = item.id
                                        showingEdit = true
                                    }
                                    Button(item.isPinned ? "当前桌面小组件" : "设为桌面小组件") {
                                        store.selectForDesktopWidget(item)
                                    }
                                    Button(item.isPaused ? "继续" : "暂停") {
                                        store.togglePause(item)
                                    }
                                    Button("删除", role: .destructive) {
                                        pendingDelete = item
                                    }
                                    .accessibilityIdentifier("timeslot.countdown.context-delete.\(item.id.uuidString)")
                                }
                            }
                        }
                        .padding(.horizontal, Space.m)
                    }
                }
                .scrollIndicators(.hidden)

                Spacer(minLength: 10)
            } else if selectedSection == .pomodoro {
                pomodoroSidebar
            } else {
                settingsSidebar
            }

        }
        .frame(width: 276)
        .frame(maxHeight: .infinity, alignment: .top)
        .glassBoard(wash: store.accentPreset.color)
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Label("偏好设置", systemImage: "slider.horizontal.3")
                .font(AppType.ui(Typo.body, .medium))
                .tracking(Tracking.heading)
            Text("提醒、桌面小组件和番茄钟节奏都可以在这里调整，改动会立即生效并同步到小组件。")
                .font(AppType.ui(Typo.footnote))
                .foregroundStyle(.secondary)
                .lineSpacing(2.5)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: Space.xs) {
                Label("关于", systemImage: "info.circle")
                    .font(AppType.ui(Typo.footnote, .medium))
                    .foregroundStyle(.secondary)
                Text(appVersionText)
                    .font(AppType.caption())
                    .foregroundStyle(.secondary)
            }
            .padding(Space.l)
            .cardSurface()
            .padding(.horizontal, Space.m)
            .padding(.bottom, Space.l)
        }
        .padding(.horizontal, Space.xl)
        .padding(.top, Space.l)
    }

    private var appVersionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return "时隙 \(version) (\(build))"
    }

    private var pomodoroSidebar: some View {
        let state = store.pomodoro
        let ink: Color = {
            if state.isStopwatchActive { return stopwatchColor }
            let preset = store.accentPreset
            switch state.phase {
            case .focus: return accent
            case .shortBreak: return Color(hex: preset.breakHex)
            case .longBreak: return Color(hex: preset.longBreakHex)
            }
        }()
        let sidebarProgress: CGFloat = {
            if state.isStopwatchActive {
                let elapsed = state.stopwatchElapsed(at: Date())
                return CGFloat((elapsed.truncatingRemainder(dividingBy: 60)) / 60)
            }
            return CGFloat(min(1, max(0, state.elapsed(at: Date()) / max(1, state.duration(for: state.phase)))))
        }()
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Space.m) {
                HStack {
                    Image(systemName: state.isStopwatchActive ? "stopwatch.fill" : state.phase.icon)
                        .foregroundStyle(ink.opacity(0.72))
                    Text(state.isStopwatchActive ? "正计时" : state.phase.title)
                        .font(AppType.ui(Typo.body, .medium))
                    Spacer()
                    Circle()
                        .fill(
                            (state.isStopwatchActive ? state.stopwatchRunning : state.isRunning)
                            ? ink
                            : Color.secondary.opacity(0.35)
                        )
                        .frame(width: 8, height: 8)
                        .shadow(color: (state.isStopwatchActive ? state.stopwatchRunning : state.isRunning) ? ink.opacity(0.5) : .clear, radius: 3)
                }
                Text(
                    state.isStopwatchActive
                        ? (state.stopwatchRunning ? "正在计时" : "已暂停")
                        : (state.isRunning ? "正在计时" : (state.sessionStartedAt == nil ? "等待开始" : "已暂停"))
                )
                    .font(AppType.ui(Typo.footnote, .medium))
                    .foregroundStyle(.secondary)
                TimeSlotProgressBar(
                    progress: sidebarProgress,
                    color: ink.opacity(0.72),
                    height: 5,
                    showsKnob: false
                )
            }
            .padding(Space.l)
            .cardSurface()
            .padding(.horizontal, Space.l)

            VStack(alignment: .leading, spacing: Space.s) {
                Label("当前节奏", systemImage: "repeat")
                    .font(AppType.ui(Typo.footnote, .medium))
                    .tracking(Tracking.label)
                    .foregroundStyle(.secondary)
                Text("\(state.focusMinutes) 分钟专注 · \(state.shortBreakMinutes) 分钟短休息")
                    .font(AppType.ui(Typo.footnote))
                    .foregroundStyle(.secondary)
                Text("每 \(state.roundsBeforeLongBreak) 轮进入 \(state.longBreakMinutes) 分钟长休息")
                    .font(AppType.ui(Typo.footnote))
                    .foregroundStyle(.secondary)
                Text("本周专注目标 \(max(1, state.weeklyFocusGoalMinutes / 60)) 小时")
                    .font(AppType.ui(Typo.footnote))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Space.xl)
            .padding(.top, Space.l)

            Spacer()
        }
    }

    private var homeDashboard: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            homeCommandDeck

            HStack(alignment: .top, spacing: Space.xl) {
                homeCalendarBoard
                    .frame(maxWidth: .infinity)

                homeSignalDeck
                    .frame(width: 300)
            }

            homeTrendCard
        }
        .padding(.horizontal, 4)
        .padding(.bottom, Space.xl)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var homeCommandDeck: some View {
        let next = upcomingCountdowns.first ?? store.selectedItem ?? store.items.first
        let state = store.pomodoro
        let goalHours = max(1, state.weeklyFocusGoalMinutes / 60)

        return HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: Space.m) {
                HStack(alignment: .center) {
                    Label("下一目标", systemImage: "calendar.badge.clock")
                        .font(AppType.ui(Typo.footnote, .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        if next == nil {
                            showingAdd = true
                        } else {
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                                selectedSection = .countdown
                            }
                        }
                    } label: {
                        Image(systemName: next == nil ? "plus" : "arrow.up.right")
                            .font(AppType.ui(13, .semibold))
                            .frame(width: 30, height: 30)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(TimeSlotPressableStyle())
                    .inkPill()
                    .help(next == nil ? "新建倒计时" : "打开倒计时")
                    .accessibilityLabel(next == nil ? "新建倒计时" : "打开倒计时")
                }

                if let next {
                    // 这里的文案只显示天/小时/分钟，无需每秒触发布局。
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        let remaining = next.remaining(at: context.date)
                        let progress = CGFloat(min(1, max(0.02, 1 - remaining / max(1, next.totalDuration))))

                        VStack(alignment: .leading, spacing: Space.s) {
                            Text(next.title)
                                .font(AppType.pageTitle(26))
                                .lineLimit(1)
                            HStack(alignment: .lastTextBaseline, spacing: Space.m) {
                                Text(remaining > 0 ? homeRemaining(remaining) : "已到达")
                                    .font(AppType.timer(52))
                                    .monospacedDigit()
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.62)
                                Text(beijingDateString(next.targetDate, dateStyle: .abbreviated, timeStyle: .omitted))
                                    .font(AppType.caption())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            TimeSlotProgressBar(
                                progress: progress,
                                color: DataSignal.color(hex: next.colorHex, isDark: colorScheme == .dark),
                                height: 8,
                                showsKnob: true,
                                showsMilestones: true
                            )
                            .accessibilityLabel("\(next.title) 倒计时进度")
                            .accessibilityValue("\(Int(progress * 100))%")
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: Space.s) {
                        Text("建立一个目标")
                            .font(AppType.pageTitle(26))
                        Text("让最重要的截止日固定在工作台上")
                            .font(AppType.ui(Typo.footnote))
                            .foregroundStyle(.secondary)
                    }
                    .frame(minHeight: 112, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
                .frame(height: 154)
                .padding(.horizontal, Space.xl)

            VStack(alignment: .leading, spacing: Space.m) {
                HStack {
                    Label("当前专注", systemImage: state.isStopwatchActive ? "stopwatch.fill" : state.phase.icon)
                        .font(AppType.ui(Typo.footnote, .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                            selectedSection = .pomodoro
                        }
                    } label: {
                        Image(systemName: "arrow.up.right")
                            .font(AppType.ui(13, .semibold))
                            .frame(width: 30, height: 30)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(TimeSlotPressableStyle())
                    .inkPill()
                    .help("打开专注")
                    .accessibilityLabel("打开专注")
                }

                let focusIsRunning = state.isStopwatchActive ? state.stopwatchRunning : state.isRunning
                if focusIsRunning {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        homeFocusReadout(state: state, date: context.date)
                    }
                } else {
                    // 暂停/等待时内容是静态快照，不要让首页继续保持秒级刷新。
                    homeFocusReadout(state: state, date: Date())
                }

                Text(String(format: "本周 %.1f / %d 小时", homeWeekFocusSeconds / 3600, goalHours))
                    .font(AppType.caption())
                    .foregroundStyle(.secondary)
            }
            .frame(width: 260, alignment: .leading)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .background {
            RoundedRectangle(cornerRadius: Radius.board, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.055) : Color.white.opacity(0.82))
                .overlay(alignment: .top) {
                    LinearGradient(
                        colors: [BrandPalette.gold.opacity(0.86), accent.opacity(0.42), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(height: 1)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.board, style: .continuous))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: Radius.board, style: .continuous)
                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.22 : 0.06), radius: 16, y: 6)
    }

    private var homeSignalDeck: some View {
        let todaySeconds = homeTodayFocusSeconds
        let weekHours = homeWeekFocusSeconds / 3600
        let goalHours = max(1, store.pomodoro.weeklyFocusGoalMinutes / 60)
        let topSlot = timeSlotBreakdown.max { $0.minutes < $1.minutes }

        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("工作读数", systemImage: "waveform.path.ecg")
                    .font(AppType.ui(Typo.footnote, .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("5 项信号")
                    .font(AppType.caption(10.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, Space.m)

            Divider()

            homeSignalRow(
                label: "今日专注",
                value: homeFocusDurationText(todaySeconds),
                detail: todayTaskBreakdown.prefix(2).map(\.title).joined(separator: " · ").isEmpty
                    ? "尚未记录专注"
                    : todayTaskBreakdown.prefix(2).map(\.title).joined(separator: " · "),
                color: DataGradient.base(0)
            )

            Divider()

            homeTaskDistributionRow

            Divider()

            homeSignalRow(
                label: "连续专注",
                value: "\(streakDays) 天",
                detail: streakDays > 0 ? "今天也在延续" : "从一次专注开始",
                color: DataGradient.base(1)
            )

            Divider()

            homeSignalRow(
                label: "本周累计",
                value: String(format: "%.1f 小时", weekHours),
                detail: String(format: "目标 %d 小时", goalHours),
                color: DataGradient.base(2),
                progress: CGFloat(min(1, homeWeekFocusSeconds / max(1, Double(goalHours * 3600))))
            )

            Divider()

            homeSignalRow(
                label: "高效时段",
                value: topSlot?.label ?? "--",
                detail: topSlot.map { homeFocusDurationText($0.minutes * 60) } ?? "近 7 天暂无数据",
                color: DataGradient.base(3)
            )

            Divider()

            HStack(spacing: Space.s) {
                Image(systemName: "checkmark.circle.fill")
                    .font(AppType.caption(11, weight: .semibold))
                    .foregroundStyle(BrandPalette.teal)
                Text("本地记录 · 实时同步")
                    .font(AppType.caption(10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("北京时间")
                    .font(AppType.caption(10))
                    .foregroundStyle(.tertiary)
            }
            .padding(.top, Space.s)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .glassBoard(wash: BrandPalette.teal)
    }

    private var homeTaskDistributionRow: some View {
        let points = todayTaskBreakdown
        let total = max(1, points.reduce(0) { $0 + $1.minutes })

        return VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .firstTextBaseline) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(DataGradient.base(4))
                    .frame(width: 3, height: 15)
                Text("任务分布")
                    .font(AppType.caption(11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(points.isEmpty ? "--" : "今日")
                    .font(AppType.caption(10.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if points.isEmpty {
                Text("完成一个阶段后显示任务占比")
                    .font(AppType.caption(10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                VStack(spacing: 5) {
                    ForEach(Array(points.prefix(2).enumerated()), id: \.offset) { index, point in
                        HStack(spacing: Space.s) {
                            Text(point.title)
                                .font(AppType.caption(10.5, weight: .medium))
                                .foregroundStyle(.primary.opacity(0.78))
                                .lineLimit(1)
                                .frame(width: 44, alignment: .leading)
                            GeometryReader { proxy in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.primary.opacity(0.08))
                                    Capsule()
                                        .fill(point.color.opacity(0.88))
                                        .frame(width: proxy.size.width * CGFloat(point.minutes / total))
                                }
                            }
                            .frame(height: 5)
                            Text("\(Int((point.minutes / total) * 100))%")
                                .font(AppType.caption(10, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 30, alignment: .trailing)
                        }
                    }
                }
            }
        }
        .padding(.vertical, Space.s)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("今日任务分布")
        .accessibilityValue(
            points.isEmpty
                ? "暂无记录"
                : points.prefix(2).map { "\($0.title) \(Int(($0.minutes / total) * 100))%" }.joined(separator: "，")
        )
    }

    private func homeSignalRow(
        label: String,
        value: String,
        detail: String,
        color: Color,
        progress: CGFloat? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(color)
                    .frame(width: 3, height: 15)
                Text(label)
                    .font(AppType.caption(11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .font(AppType.ui(15, .medium))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            Text(detail)
                .font(AppType.caption(10.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let progress {
                TimeSlotProgressBar(progress: progress, color: color, height: 4, showsKnob: false)
                    .padding(.top, 1)
            }
        }
        .padding(.vertical, Space.m)
    }

    private var homeCalendarBoard: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            HomeHourTimeline(store: store, currentDate: context.date) {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                    selectedSection = .pomodoro
                }
            }
        }
    }

    private func homeMiniBoard<Content: View>(
        title: String,
        actionTitle: String,
        wash: Color = .clear,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(AppType.pageTitle(15))
                    .tracking(0.2)
                Spacer()
                Button(actionTitle, action: action)
                    .font(AppType.caption())
                    .foregroundStyle(.secondary)
                    .buttonStyle(TimeSlotPressableStyle())
            }
            content()
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassBoard(wash: wash)
    }

    private var homeTodayRingCard: some View {
        let points = todayTaskBreakdown
        let totalMinutes = points.reduce(0) { $0 + $1.minutes }

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("今日分布")
                    .font(AppType.pageTitle(15))
                    .tracking(0.2)
                Spacer()
            }
            if totalMinutes >= 1 {
                Chart(points, id: \.title) { point in
                    SectorMark(
                        angle: .value("分钟", point.minutes),
                        innerRadius: .ratio(0.62),
                        angularInset: 1.5
                    )
                    .foregroundStyle(by: .value("任务", point.title))
                    .cornerRadius(2)
                }
                .chartForegroundStyleScale(
                    domain: points.map(\.title),
                    range: points.map(\.color)
                )
                .chartLegend(.hidden)
                .frame(height: 84)
                .overlay(alignment: .center) {
                    VStack(spacing: 0) {
                        Text("\(Int(totalMinutes))")
                            .font(.system(size: 21, weight: .light, design: .serif))
                        Text("分钟")
                            .font(AppType.caption(9.5))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(points.prefix(2).map(\.title).joined(separator: " · "))
                    .font(AppType.caption())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            } else {
                Text("今天还没有专注记录")
                    .font(AppType.ui(13))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .glassBoard(wash: DataGradient.base(0))
    }

    private var homeStreakCard: some View {
        let days = streakDays

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("连续专注")
                    .font(AppType.pageTitle(15))
                    .tracking(0.2)
                Spacer()
                Image(systemName: "flame.fill")
                    .font(AppType.ui(15, .medium))
                    .foregroundStyle(DataGradient.base(1))
            }
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(days)")
                    .font(.system(size: 42, weight: .light, design: .serif))
                Text("天")
                    .font(AppType.ui(14))
                    .foregroundStyle(.secondary)
            }
            Text(days > 0 ? "保持节奏，今天是新的延续" : "今天完成一个阶段即可开启")
                .font(AppType.caption())
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .glassBoard(wash: DataGradient.base(1))
    }

    private var homeTimeSlotCard: some View {
        let slots = timeSlotBreakdown
        let maxMinutes = max(1, slots.map(\.minutes).max() ?? 1)
        let best = slots.max { $0.minutes < $1.minutes }

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("时段分布")
                    .font(AppType.pageTitle(15))
                    .tracking(0.2)
                Spacer()
                if let best, best.minutes > 0 {
                    Label(best.label, systemImage: best.icon)
                        .font(AppType.caption(10.5, weight: .semibold))
                        .foregroundStyle(DataGradient.base(2))
                }
            }
            VStack(spacing: 9) {
                ForEach(Array(slots.enumerated()), id: \.offset) { index, slot in
                    HStack(spacing: 7) {
                        Image(systemName: slot.icon)
                            .font(AppType.caption(10))
                            .foregroundStyle(.secondary)
                            .frame(width: 14)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.primary.opacity(0.08))
                                Capsule()
                                    .fill(DataGradient.palette(index)[0].opacity(0.85))
                                    .frame(width: geo.size.width * CGFloat(slot.minutes / maxMinutes))
                            }
                        }
                        .frame(height: 8)
                        Text(slot.minutes >= 60 ? String(format: "%.1fh", slot.minutes / 60) : "\(Int(slot.minutes))m")
                            .font(AppType.caption(10))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 34, alignment: .trailing)
                    }
                }
            }
            Text("近 7 天 · 按开始时段")
                .font(AppType.caption())
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .glassBoard(wash: DataGradient.base(2))
    }

    private var homeWeekTotalCard: some View {
        let seconds = homeWeekFocusSeconds
        let hours = seconds / 3600
        let goalHours = max(1, store.pomodoro.weeklyFocusGoalMinutes / 60)
        let progress = CGFloat(min(1, seconds / max(1, Double(goalHours * 3600))))

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("本周累计")
                    .font(AppType.pageTitle(15))
                    .tracking(0.2)
                Spacer()
                Text(String(format: "%.1f / %d 小时", hours, goalHours))
                    .font(AppType.caption(11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(DataGradient.base(3))
            }
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(String(format: "%.1f", hours))
                    .font(.system(size: 34, weight: .light, design: .serif))
                Text("小时")
                    .font(AppType.ui(13))
                    .foregroundStyle(.secondary)
            }
            TimeSlotProgressBar(
                progress: progress,
                color: DataGradient.base(3),
                height: 7,
                showsKnob: false
            )
            Text(String(format: "日均 %.1f 小时 · 目标 %d 小时", hours / 7, goalHours))
                .font(AppType.caption())
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .glassBoard(wash: DataGradient.base(3))
    }

    private var homeTrendCard: some View {
        let points = weekTrendPoints

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("近 7 天专注趋势")
                    .font(AppType.pageTitle(15))
                    .tracking(0.2)
                Spacer()
                Text("北京时间 · 周一至周日")
                    .font(AppType.caption())
                    .foregroundStyle(.secondary)
            }
            Chart(points, id: \.day) { point in
                BarMark(
                    x: .value("日", point.day, unit: .day),
                    y: .value("分钟", point.minutes),
                    width: .fixed(22)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [DataGradient.base(0), DataGradient.base(4)],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .cornerRadius(4)
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 7)) {
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                        .font(AppType.caption(10))
                        .foregroundStyle(.secondary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) {
                    AxisGridLine()
                        .foregroundStyle(Surface.gridLine)
                    AxisValueLabel()
                        .font(AppType.caption(9))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 92)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .glassBoard(wash: DataGradient.base(4))
    }

    private func homeMiniMetric(eyebrow: String, value: String, footnote: String, progress: CGFloat? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow)
                .font(AppType.ui(13))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(AppType.timer(28))
                .monospacedDigit()
                .foregroundStyle(.primary)
            if let progress {
                TimeSlotProgressBar(
                    progress: progress,
                    color: store.accentPreset.color,
                    height: 5,
                    showsKnob: false
                )
                .padding(.top, 2)
            }
            Text(footnote)
                .font(AppType.caption())
                .foregroundStyle(.secondary)
        }
    }

    private var upcomingCountdowns: [CountdownItem] {
        let now = Date()
        return store.items
            .filter { !$0.isPaused && $0.remaining(at: now) > 0 }
            .sorted { $0.targetDate < $1.targetDate }
    }

    private var todayTaskBreakdown: [(title: String, minutes: Double, color: Color)] {
        let calendar = beijingCalendar
        let dayStart = calendar.startOfDay(for: Date())
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        var totals: [String: Double] = [:]
        for record in store.pomodoroHistory
        where record.phase == .focus && record.actualDuration > 0 {
            guard record.endedAt >= dayStart, record.startedAt < dayEnd else { continue }
            let title = PomodoroTaskPalette.normalized(record.taskTitle)
            totals[title, default: 0] += record.actualDuration / 60
        }
        return totals
            .filter { $0.value >= 1 }
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { (title: $0.key, minutes: $0.value, color: store.taskColor(for: $0.key)) }
    }

    private var streakDays: Int {
        let calendar = beijingCalendar
        var cursor = calendar.startOfDay(for: Date())
        if !hasFocus(on: cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            cursor = yesterday
        }
        var count = 0
        while hasFocus(on: cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    private func hasFocus(on dayStart: Date) -> Bool {
        let calendar = beijingCalendar
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        return store.pomodoroHistory.contains { record in
            record.phase == .focus
                && record.actualDuration >= 60
                && record.endedAt >= dayStart
                && record.startedAt < dayEnd
        }
    }

    private var timeSlotBreakdown: [(label: String, minutes: Double, icon: String)] {
        let calendar = beijingCalendar
        let weekAgo = calendar.date(byAdding: .day, value: -6, to: Date()) ?? Date()
        var buckets: [(label: String, minutes: Double, icon: String)] = [
            ("凌晨", 0, "moon.stars.fill"),
            ("上午", 0, "sunrise.fill"),
            ("下午", 0, "sun.max.fill"),
            ("晚上", 0, "moon.fill")
        ]
        for record in store.pomodoroHistory
        where record.phase == .focus && record.actualDuration > 0 && record.endedAt >= weekAgo {
            let hour = calendar.component(.hour, from: record.startedAt)
            let index: Int
            if hour < 6 { index = 0 } else if hour < 12 { index = 1 } else if hour < 18 { index = 2 } else { index = 3 }
            buckets[index].minutes += record.actualDuration / 60
        }
        return buckets
    }

    private var weekTrendPoints: [(day: Date, minutes: Double)] {
        let calendar = beijingCalendar
        let start = PomodoroHistoryRangePolicy.weekStart(
            containing: Date(),
            calendar: calendar
        )
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start.addingTimeInterval(7 * 86_400)
        var totals: [Date: Double] = [:]
        for record in store.pomodoroHistory
        where record.phase == .focus && record.actualDuration > 0 {
            guard record.endedAt >= start, record.startedAt < end else { continue }
            let day = calendar.startOfDay(for: record.startedAt)
            totals[day, default: 0] += record.actualDuration / 60
        }
        return (0..<7).compactMap { index in
            guard let day = calendar.date(byAdding: .day, value: index, to: start) else { return nil }
            return (day: day, minutes: totals[day] ?? 0)
        }
    }

    private func homePomodoroClock(_ remaining: TimeInterval) -> String {
        let total = max(0, Int(ceil(remaining)))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private var homeWeekFocusSeconds: Double {
        let start = PomodoroHistoryRangePolicy.weekStart(containing: Date())
        let end = beijingCalendar.date(byAdding: .day, value: 7, to: start) ?? start.addingTimeInterval(7 * 86_400)
        return store.pomodoroHistory.reduce(0) { total, record in
            guard record.phase == .focus, record.actualDuration > 0 else { return total }
            guard record.endedAt > start, record.startedAt < end else { return total }
            return total + record.actualDuration
        }
    }

    private var homeTodayFocusSeconds: Double {
        let start = beijingCalendar.startOfDay(for: Date())
        let end = beijingCalendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return store.pomodoroHistory.reduce(0) { total, record in
            guard record.phase == .focus, record.actualDuration > 0 else { return total }
            guard record.endedAt > start, record.startedAt < end else { return total }
            return total + record.actualDuration
        }
    }

    private func homeFocusDurationText(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return minutes > 0 ? "\(hours)小时 \(minutes)分" : "\(hours)小时"
        }
        return "\(minutes)分钟"
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
                PomodoroView(store: store, onSyncWidget: syncPomodoroToDesktop)
            } else {
                AppSettingsPage(store: store)
            }
        }
        .id(selectedSection)
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.988)))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassBoard(wash: store.accentPreset.color)
    }

    private var countdownDetail: some View {
        return VStack(alignment: .leading, spacing: 0) {
                HStack {
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

                    TimeSlotSegmentedControl(
                        options: CountdownViewMode.allCases.map {
                            SegmentOption(id: $0.rawValue, title: $0.rawValue, value: $0)
                        },
                        selection: $countdownViewMode,
                        tint: accent
                    )
                    .frame(width: 168)

                    if let selected = store.selectedItem {
                        headerGhostButton(title: "编辑", systemImage: "slider.horizontal.3") {
                            showingEdit = true
                        }
                        .accessibilityIdentifier("timeslot.countdown.edit")

                        Button(role: .destructive) {
                            pendingDelete = selected
                        } label: {
                            Image(systemName: "trash")
                                .font(AppType.caption(12, weight: .medium))
                                .frame(width: 32, height: 32)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(TimeSlotPressableStyle())
                        .background(circleChrome)
                        .accessibilityLabel("删除倒计时")
                        .accessibilityIdentifier("timeslot.countdown.delete")
                    }
                }
                .padding(.horizontal, Space.xxl)
                .padding(.top, Space.xxl)
                .padding(.bottom, Space.xl)

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
                        VStack(alignment: .leading, spacing: 0) {
                            CountdownHero(item: selected, accent: accent)

                            Divider()
                                .padding(.vertical, Space.l)

                            HStack(spacing: Space.m) {
                                QuickActionButton(
                                    title: selected.isPinned ? "当前小组件内容" : "设为小组件内容",
                                    icon: selected.isPinned ? "checkmark.circle.fill" : "rectangle.on.rectangle",
                                    tint: accent
                                ) {
                                    pinToDesktop(selected)
                                }
                                QuickActionButton(
                                    title: selected.isPaused ? "继续倒计时" : "暂停倒计时",
                                    icon: selected.isPaused ? "play.fill" : "pause.fill",
                                    tint: selected.isPaused ? accent : Color.secondary
                                ) {
                                    store.togglePause(selected)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Divider()
                                .padding(.vertical, Space.l)

                            CountdownTimelineCard(item: selected, accent: accent)

                            Divider()
                                .padding(.vertical, Space.l)

                            infoSection(selected)
                        }
                        .padding(Space.xl)
                        .cardSurface(
                            cornerRadius: Radius.board,
                            borderOpacity: 0.08,
                            shadowRadius: 16,
                            shadowY: 5
                        )
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
                                .font(AppType.ui(12.5, .medium))
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

    private func infoSection(_ item: CountdownItem) -> some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Text("目标信息")
                .font(AppType.ui(Typo.body, .medium))
                .tracking(Tracking.heading)
                .foregroundStyle(.secondary)
            HStack(spacing: 0) {
                InfoCell(
                    label: "目标时间",
                    value: beijingDateString(item.targetDate, dateStyle: .abbreviated, timeStyle: .shortened),
                    icon: "calendar"
                )
                Divider().frame(height: 42)
                // 状态只在目标到达时变化，分钟级刷新足够。
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    let isActive = item.remaining(at: context.date) > 0
                    InfoCell(
                        label: "状态",
                        value: item.isPaused ? "已暂停" : (isActive ? "进行中" : "已结束"),
                        icon: item.isPaused ? "pause.circle" : (isActive ? "bolt.fill" : "checkmark.circle")
                    )
                }
                Divider().frame(height: 42)
                InfoCell(
                    label: "桌面小组件",
                    value: item.isPinned ? "当前固定目标" : "未选用",
                    icon: item.isPinned ? "rectangle.3.group.fill" : "rectangle.3.group"
                )
            }
            .padding(.vertical, Space.s)
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
            result.append(RoadmapGroup(title: "已到达目标", icon: "checkmark.circle.fill", color: .green, items: completed))
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
                        ForEach(groups) { group in
                            VStack(alignment: .leading, spacing: Space.m) {
                                HStack(spacing: Space.s) {
                                    Image(systemName: group.icon)
                                        .font(AppType.ui(13, .semibold))
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
        DataSignal.color(hex: item.colorHex, isDark: colorScheme == .dark)
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
                        color: item.isPaused ? .secondary : (isDone ? .green : itemColor)
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
                                .font(AppType.caption(10, weight: .semibold))
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
                                .font(AppType.caption(10, weight: .semibold))
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
        if d > 0 { return "剩 \(d)天 \(h)小时" }
        if h > 0 { return "剩 \(h)小时 \(m)分" }
        return "剩 \(m)分"
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
                        .font(AppType.ui(14, .semibold))
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
            Picker("小组件尺寸", selection: $simulatorSize) {
                ForEach(WidgetSimulatorSize.allCases) { size in
                    Text(size.rawValue).tag(size)
                }
            }
            .pickerStyle(.segmented)
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
            DataSignal.color(hex: $0.colorHex, isDark: colorScheme == .dark)
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
                    .font(AppType.ui(13, .semibold))
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
                            .font(AppType.ui(14, .semibold))
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
                        .font(AppType.ui(15, .semibold))
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

struct CountdownRow: View {
    let item: CountdownItem
    let isSelected: Bool
    let accent: Color
    let action: () -> Void

    var body: some View {
        let initialRemaining = item.remaining(at: Date())
        let needsLiveRefresh = !item.isPaused && initialRemaining > 0 && initialRemaining <= 86400

        Button(action: action) {
            if needsLiveRefresh {
                // 侧栏只是辅助读数，不需要为每个临近目标每秒重排一整行。
                // 15 秒仍能保持秒数有响应，同时把多个目标同时临近时的刷新量降一个数量级。
                TimelineView(.periodic(from: .now, by: 15)) { context in
                    rowContent(remaining: item.remaining(at: context.date))
                }
            } else {
                rowContent(remaining: initialRemaining)
            }
        }
        .buttonStyle(TimeSlotPressableStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(
            item.isPaused
                ? "已暂停，\(remainingTextValue(item.remaining(at: Date())))"
                : remainingTextValue(item.remaining(at: Date()))
        )
    }

    private func rowContent(remaining: TimeInterval) -> some View {
        let isUrgent = remaining > 0 && remaining < 86400 && !item.isPaused

        return HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(isSelected ? 0.10 : 0.055))
                    .frame(width: 26, height: 26)

                Image(systemName: item.isPaused ? "pause.fill" : (item.isPinned ? "pin.fill" : "calendar"))
                    .font(AppType.caption(10, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.72))
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(item.title)
                        .font(AppType.ui(13, isSelected ? .semibold : .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if item.isPinned {
                        Image(systemName: "rectangle.3.group.fill")
                            .font(AppType.caption(9))
                            .foregroundStyle(.secondary)
                    }
                }
                rowProgress(remaining)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 2) {
                Text(remaining > 0 ? (remaining >= 86400 ? "\(max(1, Int(remaining / 86400))) 天" : formatCompact(remaining)) : "已到达")
                    .font(AppType.caption(12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(remaining <= 0 ? Color.secondary : (isUrgent ? Color.orange : Color.primary.opacity(0.78)))

                if isUrgent {
                    Text("今天")
                        .font(AppType.caption(9, weight: .semibold))
                        .foregroundStyle(Color.orange)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.primary.opacity(0.06) : Color.clear)
        )
    }

    private func rowProgress(_ remaining: TimeInterval) -> some View {
        let total = max(1, item.totalDuration)
        let prog = remaining <= 0 ? 1.0 : min(1.0, max(0.0, 1.0 - remaining / total))
        return TimeSlotProgressBar(
            progress: CGFloat(prog),
            color: accent,
            height: 5,
            showsKnob: false,
            animatesProgress: false
        )
        .frame(width: 88)
    }

    private func remainingTextValue(_ remaining: TimeInterval) -> String {
        remaining > 0 ? formatCompact(remaining) : "已结束"
    }

    private func formatCompact(_ value: TimeInterval) -> String {
        let total = max(0, Int(ceil(value)))
        let d = total / 86400
        let h = (total % 86400) / 3600
        let m = (total % 3600) / 60
        if d > 0 { return "\(d)天 \(h)小时" }
        if h > 0 { return "\(h)小时 \(m)分" }
        return "\(m)分 \(total % 60)秒"
    }
}

/// 倒计时主卡片：模块化时间单元卡（天/时/分/秒）+ 进度条 + 状态徽章 + 彩带微动效
struct CountdownHero: View {
    let item: CountdownItem
    let accent: Color
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    var body: some View {
        let remaining = item.remaining(at: Date())
        if item.isPaused || remaining <= 0 {
            // 已暂停或已完成的目标不会再变化，不需要保留秒级时间线。
            card(remaining: remaining)
        } else {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                card(remaining: item.remaining(at: context.date))
            }
        }
    }

    private func card(remaining: TimeInterval) -> some View {
        let isDone = remaining <= 0
        let percent = Int((progressValue(remaining) * 100).rounded())

        return VStack(alignment: .leading, spacing: Space.xl) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Space.s) {
                    HStack(spacing: Space.s) {
                        Text(item.isPaused ? "倒计时已暂停" : (isDone ? "目标已到达" : "距离目标还有"))
                            .font(AppType.ui(Typo.body, .medium))
                            .foregroundStyle(.secondary)

                        StatusPillBadge(
                            title: item.isPaused ? "已暂停" : (isDone ? "已完成" : "进行中 \(percent)%"),
                            icon: item.isPaused ? "pause.circle" : (isDone ? "checkmark.circle.fill" : nil),
                            color: item.isPaused ? .secondary : (isDone ? .green : accent),
                            isPulsing: !item.isPaused && !isDone
                        )
                    }

                    if isDone {
                        HStack(spacing: Space.m) {
                            Image(systemName: "flag.checkered.circle.fill")
                                .font(AppType.ui(38))
                                .foregroundStyle(Color.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("目标达成")
                                    .font(AppType.title(Typo.sheetTitle))
                                    .foregroundStyle(.primary)
                                Text("已于 \(beijingDateString(item.targetDate, dateStyle: .long, timeStyle: .shortened)) 到达")
                                    .font(AppType.caption())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, Space.s)
                    } else {
                        modularTimeGrid(remaining: remaining)
                    }
                }

                Spacer()

                ZStack {
                    Circle()
                        .fill(accent.opacity(0.14))
                        .frame(width: 54, height: 54)
                    Image(systemName: isDone ? "checkmark.circle.fill" : (item.isPaused ? "pause.fill" : "timer"))
                        .font(AppType.ui(Typo.icon, .medium))
                        .foregroundStyle(accent)
                        .symbolEffect(.pulse, isActive: !isDone && !item.isPaused && !reduceMotion)
                }
            }

            VStack(alignment: .leading, spacing: Space.s) {
                HStack {
                    Text("进度 \(percent)%")
                        .font(AppType.caption(12, weight: .semibold))
                        .foregroundStyle(accent)
                    Spacer()
                    Text("总周期 \(formattedTotalDays)")
                        .font(AppType.caption(12, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                TimeSlotProgressBar(
                    progress: progressValue(remaining),
                    color: accent,
                    height: 10,
                    showsKnob: true,
                    showsMilestones: true,
                    animatesProgress: false
                )
            }

            HStack {
                Label(beijingDateString(item.targetDate, dateStyle: .complete, timeStyle: .shortened), systemImage: "calendar")
                    .font(AppType.ui(Typo.footnote, .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("北京时间 (UTC+8)")
                    .font(AppType.caption())
                    .foregroundStyle(.secondary)
            }
        }
        .overlay {
            ConfettiEffectView(isActive: isDone)
        }
    }

    private var formattedTotalDays: String {
        let days = Int(ceil(item.totalDuration / 86400))
        return "\(max(1, days)) 天"
    }

    @ViewBuilder
    private func modularTimeGrid(remaining: TimeInterval) -> some View {
        let total = max(0, Int(ceil(remaining)))
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        HStack(spacing: Space.s) {
            if days > 0 {
                TimeDigitBlock(value: String(format: "%d", days), label: "天", color: accent)
            }
            TimeDigitBlock(value: String(format: "%02d", hours), label: "时", color: accent)
            TimeDigitBlock(value: String(format: "%02d", minutes), label: "分", color: accent)
            TimeDigitBlock(value: String(format: "%02d", seconds), label: "秒", color: accent)
        }
    }

    private func progressValue(_ remaining: TimeInterval) -> CGFloat {
        let span = max(item.totalDuration, 1)
        return remaining <= 0 ? 1 : min(1, max(0.04, 1 - remaining / span))
    }
}


/// 倒计时时间轴卡片：展示从创建时间到目标日期的全生命周期
struct CountdownTimelineCard: View {
    let item: CountdownItem
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("时间里程碑")
                .font(AppType.ui(Typo.body, .medium))
                .tracking(Tracking.heading)
                .foregroundStyle(.secondary)

            let initialRemaining = item.remaining(at: Date())
            VStack(spacing: Space.m) {
                // 已暂停或已完成的目标不会变化，不需要保留分钟级时间线。
                if item.isPaused || initialRemaining <= 0 {
                    milestoneContent(remaining: initialRemaining)
                } else {
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        milestoneContent(remaining: item.remaining(at: context.date))
                    }
                }
            }
        }
    }

    private func milestoneContent(remaining: TimeInterval) -> some View {
        let total = max(1, item.totalDuration)
        let elapsed = max(0, total - remaining)
        let elapsedDays = Int(elapsed / 86400)
        let remainingDays = Int(ceil(remaining / 86400))

        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("起始点")
                    .font(AppType.caption())
                    .foregroundStyle(.secondary)
                Text(beijingDateString(item.createdAt, dateStyle: .abbreviated, timeStyle: .omitted))
                    .font(AppType.ui(Typo.footnote, .medium))
            }

            Spacer()

            VStack(spacing: 2) {
                Text("已过去 \(elapsedDays) 天 · 剩余 \(max(0, remainingDays)) 天")
                    .font(AppType.caption(11.5, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.72))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("目标点")
                    .font(AppType.caption())
                    .foregroundStyle(.secondary)
                Text(beijingDateString(item.targetDate, dateStyle: .abbreviated, timeStyle: .omitted))
                    .font(AppType.ui(Typo.footnote, .medium))
            }
        }
    }
}

struct QuickActionButton: View {
    let title: String
    let icon: String
    let tint: Color
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(AppType.ui(12.5, .medium))
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
                                        .fill(DataSignal.color(hex: option.hex, isDark: colorScheme == .dark))
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
                                                    .font(AppType.caption(10, weight: .bold))
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
                        .fill(DataSignal.color(hex: colorHex, isDark: colorScheme == .dark))
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
                        .foregroundStyle(DataSignal.color(hex: colorHex, isDark: colorScheme == .dark))
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
                    .tint(DataSignal.color(hex: colorHex, isDark: colorScheme == .dark))
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
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var pan = CGSize.zero
    @State private var scaleX: CGFloat = 1
    @State private var scaleY: CGFloat = 1
    @GestureState private var drag = CGSize.zero
    @State private var hovering = false
    // 指针位置只供缩放手势使用，不发布为 SwiftUI 状态，避免连续 hover 触发整张时间轴重绘。
    @State private var interactionState = TimelineInteractionState()
    @State private var scrollMonitor: Any?
    @State private var lastPlotWidth: CGFloat = 0
    @State private var lastWorldWidth: CGFloat = 0
    @State private var pinchStartScaleX: CGFloat = 1
    @State private var pinchStartScaleY: CGFloat = 1
    @State private var pinchStartPan = CGSize.zero
    @State private var isPinching = false

    private let hourGutter: CGFloat = 36
    private let headerHeight: CGFloat = 42
    private let fillDayCount: CGFloat = 7

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("时间轴")
                    .font(AppType.pageTitle(22))
                    .tracking(-0.3)
                Spacer()
                Button("回到今天") {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.9)) {
                        scaleX = 1
                        scaleY = 1
                        pan = CGSize(width: min(0, lastPlotWidth - lastWorldWidth), height: 0)
                    }
                }
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.secondary)
                .buttonStyle(TimeSlotPressableStyle())
            }

            GeometryReader { geo in
                let days = timelineDays(at: currentDate)
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
                let blocks = timelineBlocks(days: days, at: currentDate)
                let dailyTotals = dailyMinutes(blocks: blocks, dayCount: days.count)

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
                            ForEach(Array(dailyTotals.enumerated()), id: \.offset) { index, minutes in
                                if minutes >= 30 {
                                    Text(minutes >= 60 ? String(format: "%.1fh", minutes / 60) : "\(Int(minutes))m")
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .monospacedDigit()
                                        .foregroundStyle(minutes >= 180 ? store.accentPreset.color : Color.secondary.opacity(0.9))
                                        .position(x: CGFloat(index) * dayWidth + dayWidth / 2, y: worldHeight - 10)
                                        .allowsHitTesting(false)
                                }
                            }
                            nowLine(days: days, dayWidth: dayWidth, hourHeight: hourHeight, date: currentDate)
                        }
                        .frame(width: worldWidth, height: worldHeight, alignment: .topLeading)
                        .offset(clamped)
                        .frame(width: plotWidth, height: plotHeight, alignment: .topLeading)
                        .clipped()
                        .contentShape(Rectangle())
                        .gesture(panGesture)
                        .simultaneousGesture(zoomGesture)
                        .animation(reduceMotion ? nil : .interactiveSpring(response: 0.18, dampingFraction: 1.0), value: scaleX)
                        .animation(reduceMotion ? nil : .interactiveSpring(response: 0.18, dampingFraction: 1.0), value: scaleY)
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
                    pan = CGSize(width: min(0, plotWidth - worldWidth), height: 0)
                    lastPlotWidth = plotWidth
                    lastWorldWidth = worldWidth
                    installScrollMonitor()
                }
                .onChange(of: worldWidth) { _, newWidth in
                    lastWorldWidth = newWidth
                    lastPlotWidth = plotWidth
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
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 340, alignment: .topLeading)
        .background(alignment: .topTrailing) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            DataGradient.base(0).opacity(colorScheme == .dark ? 0.10 : 0.12),
                            DataGradient.base(1).opacity(colorScheme == .dark ? 0.05 : 0.06)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
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
                pan.width += value.translation.width
                pan.height += value.translation.height
            }
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                if !isPinching {
                    isPinching = true
                    pinchStartScaleX = scaleX
                    pinchStartScaleY = scaleY
                    pinchStartPan = pan
                }
                zoom(
                    fromScaleX: pinchStartScaleX,
                    fromScaleY: pinchStartScaleY,
                    fromPan: pinchStartPan,
                    factorX: value,
                    factorY: value,
                    around: interactionState.hoverPoint,
                    dayCount: timelineDays().count
                )
            }
            .onEnded { _ in
                isPinching = false
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
        let widthFactor = nextX / max(fromScaleX, 0.001)
        let heightFactor = nextY / max(fromScaleY, 0.001)
        scaleX = nextX
        scaleY = nextY
        pan.width = focal.x - (focal.x - fromPan.width) * widthFactor
        pan.height = focal.y - (focal.y - fromPan.height) * heightFactor
    }

    private func clampPan(_ value: CGSize, plotWidth: CGFloat, plotHeight: CGFloat, worldWidth: CGFloat, worldHeight: CGFloat) -> CGSize {
        let minX = min(0, plotWidth - worldWidth)
        let minY = min(0, plotHeight - worldHeight)
        return CGSize(
            width: min(0, max(minX, value.width)),
            height: min(0, max(minY, value.height))
        )
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
            let tickCount = 17

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 4)

                HStack(spacing: 0) {
                    ForEach(0..<tickCount, id: \.self) { index in
                        Rectangle()
                            .fill(Color.primary.opacity(index % 4 == 0 ? 0.30 : 0.14))
                            .frame(width: 1, height: index % 4 == 0 ? 4 : 2.5)
                        if index < tickCount - 1 { Spacer(minLength: 0) }
                    }
                }
                .padding(.horizontal, 5)
                .frame(height: 4)

                Capsule()
                    .fill(Color.primary.opacity(0.40))
                    .frame(width: thumbWidth, height: 4)
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
                        .font(.system(size: 11, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("\(beijingCalendar.component(.day, from: day))")
                        .font(.system(size: 14, weight: isToday ? .regular : .ultraLight, design: .default))
                        .foregroundStyle(isToday ? Color.primary : Color.primary.opacity(0.62))
                }
                .frame(width: dayWidth, height: headerHeight)
            }
        }
    }

    private func hourGutterView(hourHeight: CGFloat, hourStep: Int) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                Text(hour % hourStep == 0 ? String(format: "%02d", hour) : "")
                    .font(.system(size: 11, weight: .light, design: .default))
                    .foregroundStyle(.secondary)
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
        return Button(action: onOpenFocus) {
            Group {
                if height > 24 && laneWidth > 46 {
                    Text(block.title)
                        .font(.system(size: 11, weight: .regular))
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
            .help("\(block.title)  \(block.timeLabel)")
        }
        .buttonStyle(TimeSlotPressableStyle())
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

    private func dailyMinutes(blocks: [TimelineBlock], dayCount: Int) -> [Double] {
        var totals = Array(repeating: 0.0, count: dayCount)
        for block in blocks where !block.live {
            totals[block.dayIndex] += block.durationHours * 60
        }
        return totals
    }

    private func installScrollMonitor() {
        removeScrollMonitor()
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify]) { event in
            guard hovering else { return event }
            if event.type == .magnify {
                let factor = 1 + event.magnification
                zoom(
                    fromScaleX: scaleX,
                    fromScaleY: scaleY,
                    fromPan: pan,
                    factorX: factor,
                    factorY: factor,
                    around: interactionState.hoverPoint,
                    dayCount: timelineDays().count
                )
                return nil
            }
            if event.modifierFlags.contains(.command) {
                // ⌘+滚轮：水平缩放；加 Shift 只缩放垂直。
                let factor = event.scrollingDeltaY > 0 ? 1.045 : 0.957
                zoom(
                    fromScaleX: scaleX,
                    fromScaleY: scaleY,
                    fromPan: pan,
                    factorX: event.modifierFlags.contains(.shift) ? 1 : factor,
                    factorY: event.modifierFlags.contains(.shift) ? factor : 1,
                    around: interactionState.hoverPoint,
                    dayCount: timelineDays().count
                )
                return nil
            }
            // 普通滚轮：上下滚动直接缩放时间轴高度，左右滚动平移。
            // 缩放幅度跟随滚动速度，滚动越快缩放越快，手感更自然。
            if event.scrollingDeltaY != 0 {
                let magnitude = min(abs(event.scrollingDeltaY), 60)
                let factor = 1 + magnitude * 0.003 * (event.scrollingDeltaY > 0 ? 1 : -1)
                zoom(
                    fromScaleX: scaleX,
                    fromScaleY: scaleY,
                    fromPan: pan,
                    factorX: 1,
                    factorY: factor,
                    around: interactionState.hoverPoint,
                    dayCount: timelineDays().count
                )
            }
            if event.scrollingDeltaX != 0 {
                pan.width += event.scrollingDeltaX
            }
            return nil
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
                    : PomodoroTaskPalette.fallbackColorHex(for: title),
                isDark: colorScheme == .dark
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
                            id: "\(title)-\(day.timeIntervalSinceReferenceDate)-\(startHour)",
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
        let names = ["日", "一", "二", "三", "四", "五", "六"]
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
