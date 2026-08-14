import AppKit
import SwiftUI
import Combine
import WidgetKit
import Charts

struct BrandMark: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [BrandPalette.ink, BrandPalette.deepTeal, Color(hex: "#145754")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.13), Color.clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                )

            // 两条时间带围绕中心错位，中央金色缺口就是“时隙”。
            RoundedRectangle(cornerRadius: size * 0.052, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [BrandPalette.mint, BrandPalette.teal],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size * 0.32, height: size * 0.12)
                .offset(x: -size * 0.175, y: -size * 0.055)

            RoundedRectangle(cornerRadius: size * 0.052, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [BrandPalette.mint, BrandPalette.teal],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size * 0.32, height: size * 0.12)
                .offset(x: size * 0.175, y: size * 0.055)

            Path { path in
                path.move(to: CGPoint(x: size * 0.455, y: size * 0.39))
                path.addLine(to: CGPoint(x: size * 0.545, y: size * 0.48))
                path.addLine(to: CGPoint(x: size * 0.545, y: size * 0.61))
                path.addLine(to: CGPoint(x: size * 0.455, y: size * 0.52))
                path.closeSubpath()
            }
            .fill(
                LinearGradient(
                    colors: [Color(hex: "#F3D69B"), BrandPalette.gold],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )

            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.16), Color.white.opacity(0.025)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: max(0.5, size * 0.018)
                )
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
    @State private var selectedSection: TimeBookSection = .countdown
    @State private var showingCopiedFeedback = false
    @FocusState private var searchFieldFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail
        }
        // 系统字形负责界面阅读，计时数字在 AppType.timer 中单独使用圆体。
        .fontDesign(.default)
        .background(Surface.canvas)
        .overlay(alignment: .bottomTrailing) {
            VStack(alignment: .trailing, spacing: Space.s) {
                if showingCopiedFeedback {
                    HStack(spacing: Space.s) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(accent)
                        Text("已复制倒计时文案到剪贴板")
                            .font(AppType.ui(Typo.footnote, .medium))
                    }
                    .padding(.horizontal, Space.m)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().stroke(accent.opacity(0.25), lineWidth: 1))
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }

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
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: showingCopiedFeedback)
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

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: Space.m) {
                    BrandMark(size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("时隙")
                            .font(AppType.title(Typo.brand))
                            .tracking(Tracking.pageTitle)
                        Text("倒计时 · 专注")
                            .font(AppType.caption(Typo.footnote, weight: .medium))
                            .tracking(Tracking.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if selectedSection == .countdown {
                    Button {
                        showingAdd = true
                    } label: {
                        Image(systemName: "plus")
                            .font(AppType.ui(Typo.body, .semibold))
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                    .help("新建倒计时 (⌘N)")
                    .accessibilityLabel("新建倒计时")
                    .accessibilityIdentifier("timeslot.countdown.add")
                }
            }
            .padding(.horizontal, Space.xl)
            .padding(.top, Space.xl)
            .padding(.bottom, Space.l)

            TimeSlotSegmentedControl(
                options: [
                    SegmentOption(
                        id: TimeBookSection.countdown.rawValue,
                        title: "倒计时",
                        systemImage: "calendar.badge.clock",
                        value: TimeBookSection.countdown
                    ),
                    SegmentOption(
                        id: TimeBookSection.pomodoro.rawValue,
                        title: "番茄钟",
                        systemImage: "timer",
                        value: TimeBookSection.pomodoro
                    )
                ],
                selection: $selectedSection,
                tint: accent
            )
            .labelsHidden()
            .padding(.horizontal, Space.l)
            .padding(.bottom, Space.m)

            if selectedSection == .countdown {
                // 搜索框
                HStack(spacing: Space.s) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("搜索倒计时 (⌘F)", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(AppType.ui(Typo.body))
                        .focused($searchFieldFocused)
                        .accessibilityIdentifier("timeslot.countdown.search")
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            searchFieldFocused = true
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("清除搜索")
                    }
                }
                .padding(.horizontal, Space.m)
                .padding(.vertical, Space.s)
                .background(Surface.field)
                .clipShape(RoundedRectangle(cornerRadius: Radius.small))
                .padding(.horizontal, Space.l)
                .padding(.bottom, Space.s)

                // 状态筛选药丸栏
                HStack(spacing: 4) {
                    ForEach(CountdownFilter.allCases) { filter in
                        let isSelected = countdownFilter == filter
                        Button {
                            withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
                                countdownFilter = filter
                            }
                        } label: {
                            Text(filter.rawValue)
                                .font(AppType.caption(11.5, weight: isSelected ? .semibold : .regular))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    isSelected ? accent.opacity(0.18) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                                )
                                .foregroundStyle(isSelected ? accent : Color.secondary)
                        }
                        .buttonStyle(TimeSlotPressableStyle())
                    }
                    Spacer()
                    Text("\(filteredItems.count)")
                        .font(AppType.caption(11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(accent.opacity(0.12), in: Capsule())
                }
                .padding(.horizontal, Space.l)
                .padding(.bottom, Space.s)

                ScrollView {
                    if filteredItems.isEmpty {
                        VStack(spacing: Space.s) {
                            Image(systemName: searchText.isEmpty ? "calendar.badge.plus" : "magnifyingglass")
                                .font(AppType.ui(22, .medium))
                                .foregroundStyle(accent)
                                .padding(.bottom, Space.xs)
                            Text(searchText.isEmpty ? "还没有倒计时" : "没有匹配结果")
                                .font(AppType.ui(Typo.footnote, .semibold))
                            Text(searchText.isEmpty ? "添加一个目标，开始记录值得等待的时刻。" : "换个关键词试试。")
                                .font(AppType.caption())
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                            if searchText.isEmpty {
                                Button("新建倒计时") {
                                    showingAdd = true
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(accent)
                                .controlSize(.small)
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
                                    accent: Color(hex: item.colorHex)
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
                                    Button("复制进度") {
                                        copyCountdownSummary(item)
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

                Spacer(minLength: 10)

                VStack(alignment: .leading, spacing: Space.m) {
                    HStack {
                        Label("桌面小组件", systemImage: "macwindow.on.rectangle")
                            .font(AppType.ui(Typo.footnote, .medium))
                            .tracking(Tracking.label)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            showingWidgetHelp = true
                        } label: {
                            Text("1:1 预览")
                                .font(AppType.caption(10.5, weight: .semibold))
                                .foregroundStyle(accent)
                        }
                        .buttonStyle(.plain)
                    }
                    Text("独立倒计时组件沿用当前固定目标；如果要让多个组件显示不同目标，请添加“时隙 · 自定义”。")
                        .font(AppType.ui(Typo.footnote))
                        .lineSpacing(2.5)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    widgetModePicker
                    Button {
                        guard let item = store.selectedItem else { return }
                        pinToDesktop(item)
                    } label: {
                        Label("更新小组件内容", systemImage: "rectangle.3.group")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(accent)
                    .disabled(store.selectedItem == nil)
                    .accessibilityIdentifier("timeslot.widget.sync")
                }
                .padding(Space.l)
                .cardSurface()
                .padding(.horizontal, Space.m)
                .padding(.bottom, Space.l)
            } else if selectedSection == .pomodoro {
                pomodoroSidebar
            } else {
                settingsSidebar
            }

            Divider()
                .padding(.horizontal, Space.m)

            HStack(spacing: Space.s) {
                Button {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                        selectedSection = .settings
                    }
                } label: {
                    Label("设置", systemImage: "gearshape")
                        .font(AppType.ui(Typo.footnote, .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, Space.s)
                        .padding(.vertical, Space.s)
                        .foregroundStyle(selectedSection == .settings ? Color.white : Color.primary)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                                .fill(selectedSection == .settings ? accent : Color.clear)
                        )
                }
                .buttonStyle(TimeSlotPressableStyle())
                .accessibilityLabel("设置")
                .accessibilityIdentifier("timeslot.settings.open")
                .accessibilityValue(selectedSection == .settings ? "已选中" : "未选中")

                Button {
                    showingShortcuts = true
                } label: {
                    Image(systemName: "keyboard")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .background(Surface.nested, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
                }
                .buttonStyle(TimeSlotPressableStyle())
                .help("快捷键速查 (⌘/)")
            }
            .padding(.horizontal, Space.m)
            .padding(.bottom, Space.m)
        }
        .frame(width: 268)
        .background(SidebarSurface())
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
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return "时隙 \(version) (\(build))"
    }

    private func sidebarStopwatchTimeText(_ elapsed: TimeInterval) -> String {
        let total = max(0, Int(elapsed))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private var pomodoroSidebar: some View {
        let state = store.pomodoro
        let phaseColor = state.phase == .focus ? accent : Color(hex: state.phase.colorHex)
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
                        .foregroundStyle(state.isStopwatchActive ? stopwatchColor : phaseColor)
                    Text(state.isStopwatchActive ? "正计时" : state.phase.title)
                        .font(AppType.ui(Typo.body, .medium))
                    Spacer()
                    Circle()
                        .fill(
                            (state.isStopwatchActive ? state.stopwatchRunning : state.isRunning)
                            ? (state.isStopwatchActive ? stopwatchColor : phaseColor)
                            : Color.secondary.opacity(0.35)
                        )
                        .frame(width: 8, height: 8)
                        .shadow(
                            color: (state.isStopwatchActive ? state.stopwatchRunning : state.isRunning)
                                ? (state.isStopwatchActive ? stopwatchColor : phaseColor).opacity(0.45)
                                : .clear,
                            radius: 3
                        )
                }
                if state.isStopwatchActive {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(sidebarStopwatchTimeText(state.stopwatchElapsed(at: context.date)))
                            .font(AppType.timer(Typo.timerSmall))
                            .monospacedDigit()
                            .foregroundStyle(stopwatchColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    Text(state.stopwatchRunning ? "正在计时" : "已暂停")
                        .font(AppType.ui(Typo.footnote, .medium))
                        .foregroundStyle(.secondary)
                } else {
                    PomodoroTimerText(
                        state: state,
                        fontSize: Typo.timerSmall,
                        color: phaseColor
                    )
                    Text("已完成 \(state.completedFocusSessions) 个番茄")
                        .font(AppType.ui(Typo.footnote, .medium))
                        .foregroundStyle(.secondary)
                }
                TimeSlotProgressBar(
                    progress: sidebarProgress,
                    color: state.isStopwatchActive ? stopwatchColor : phaseColor,
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

            VStack(alignment: .leading, spacing: Space.m) {
                Label("桌面小组件", systemImage: "macwindow.on.rectangle")
                    .font(AppType.ui(Typo.footnote, .medium))
                    .tracking(Tracking.label)
                    .foregroundStyle(.secondary)
                Text("可单独添加正计时、番茄钟，或查看本周专注目标。")
                    .font(AppType.ui(Typo.footnote))
                    .lineSpacing(2)
                    .foregroundStyle(.secondary)
                widgetModePicker
                Button {
                    syncPomodoroToDesktop()
                } label: {
                    Label("更新小组件内容", systemImage: "rectangle.3.group")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(phaseColor)
            }
            .padding(Space.l)
            .cardSurface()
            .padding(.horizontal, Space.m)
            .padding(.bottom, Space.l)
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
    }

    private var countdownDetail: some View {
        ZStack {
            LinearGradient(
                colors: [
                    (store.selectedItem.map { Color(hex: $0.colorHex).opacity(0.06) } ?? Color.clear),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .center
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text("倒计时视图")
                            .font(AppType.caption(Typo.body, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(store.selectedItem?.title ?? "时隙 · 倒计时")
                            .font(AppType.pageTitle())
                            .tracking(Tracking.pageTitle)
                            .lineLimit(1)
                    }
                    Spacer()

                    // 视图切换器：卡片 / 全景时间流
                    TimeSlotSegmentedControl(
                        options: CountdownViewMode.allCases.map {
                            SegmentOption(id: $0.rawValue, title: $0.rawValue, value: $0)
                        },
                        selection: $countdownViewMode,
                        tint: accent
                    )
                    .frame(width: 170)

                    Button {
                        ZenHUDWindowController.shared.toggle(store: store)
                    } label: {
                        Label("禅模式", systemImage: "macwindow.badge.plus")
                    }
                    .buttonStyle(.bordered)
                    .help("切换独立置顶悬浮窗 (⌘M)")

                    if let selected = store.selectedItem {
                        Button {
                            copyCountdownSummary(selected)
                        } label: {
                            Label("复制", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                        .help("复制倒计时进度文案")

                        Button {
                            showingEdit = true
                        } label: {
                            Label("编辑", systemImage: "slider.horizontal.3")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("timeslot.countdown.edit")

                        Button(role: .destructive) {
                            pendingDelete = selected
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
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
                        VStack(alignment: .leading, spacing: Space.xl) {
                            CountdownHero(item: selected, accent: Color(hex: selected.colorHex))

                            HStack(spacing: Space.m) {
                                QuickActionButton(
                                    title: selected.isPinned ? "当前小组件内容" : "设为小组件内容",
                                    icon: selected.isPinned ? "checkmark.circle.fill" : "rectangle.on.rectangle",
                                    tint: Color(hex: selected.colorHex)
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
                                QuickActionButton(
                                    title: "1:1 桌面小组件预览",
                                    icon: "macwindow.on.rectangle",
                                    tint: accent
                                ) {
                                    showingWidgetHelp = true
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            CountdownTimelineCard(item: selected, accent: Color(hex: selected.colorHex))

                            infoSection(selected)
                        }
                        .padding(.horizontal, Space.xxl)
                        .padding(.bottom, Space.xxl)
                    }
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
                            Label("新建倒计时", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(accent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private func copyCountdownSummary(_ item: CountdownItem) {
        let remaining = item.remaining(at: Date())
        let remainingStr = remaining > 0 ? formatCompactTime(remaining) : "已达成"
        let dateStr = beijingDateString(item.targetDate, dateStyle: .long, timeStyle: .shortened)
        let text = "🎯 [\(item.title)] 目标时间：\(dateStr)，距离目标还有 \(remainingStr) · 来自时隙"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        showingCopiedFeedback = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            showingCopiedFeedback = false
        }
    }

    private func formatCompactTime(_ value: TimeInterval) -> String {
        let total = max(0, Int(ceil(value)))
        let d = total / 86400
        let h = (total % 86400) / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if d > 0 { return "\(d)天 \(h)小时 \(m)分" }
        if h > 0 { return "\(h)小时 \(m)分 \(s)秒" }
        return "\(m)分 \(s)秒"
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
                TimelineView(.periodic(from: .now, by: 1)) { context in
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
            .padding(.vertical, Space.m)
            .cardSurface(cornerRadius: Radius.small)
        }
    }

    /// 两个侧栏卡片共用：直接切小组件显示什么及时间单位
    private var widgetModePicker: some View {
        VStack(spacing: 0) {
            HStack(spacing: Space.s) {
                Label("内容", systemImage: "rectangle.split.2x1")
                    .font(AppType.ui(Typo.footnote, .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: Space.s)
                Picker("显示内容", selection: widgetDisplayModeSelection) {
                    ForEach(WidgetDisplayMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 82)
            }
            .padding(.vertical, 9)

            Divider()

            HStack(spacing: Space.s) {
                Label("单位", systemImage: "textformat.123")
                    .font(AppType.ui(Typo.footnote, .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: Space.s)
                Picker("倒计时单位", selection: widgetTimeUnitSelection) {
                    Text("仅天数").tag("days")
                    Text("自动").tag("auto")
                    Text("仅小时").tag("hours")
                    Text("精细").tag("precise")
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 82)
            }
            .padding(.vertical, 9)
        }
        .padding(.horizontal, Space.m)
        .background(Surface.nested)
        .clipShape(RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
    }

    private var widgetDisplayModeSelection: Binding<WidgetDisplayMode> {
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

    private var widgetTimeUnitSelection: Binding<String> {
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
        let id = UUID()
        let title: String
        let icon: String
        let color: Color
        let items: [CountdownItem]
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
            result.append(RoadmapGroup(title: "未来更长时间", icon: "star.fill", color: Color(hex: "#5A78B8"), items: later))
        }
        if !completed.isEmpty {
            result.append(RoadmapGroup(title: "已到达目标", icon: "checkmark.circle.fill", color: .green, items: completed))
        }
        return result
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            ScrollView {
                if groups.isEmpty {
                    VStack(spacing: Space.m) {
                        Image(systemName: "calendar.badge.plus")
                            .font(.system(size: 36))
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
                                        .font(.system(size: 13, weight: .semibold))
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

    private var itemColor: Color { Color(hex: item.colorHex) }

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
                                .font(.system(size: 10, weight: .semibold))
                                .frame(width: 22, height: 22)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .help(item.isPaused ? "继续" : "暂停")

                        Button {
                            onEdit()
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 10, weight: .semibold))
                                .frame(width: 22, height: 22)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .help("编辑")

                        Button("查看详情") {
                            onSelect()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(itemColor)
                        .controlSize(.mini)
                    }
                }

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = item.remaining(at: context.date)
                    let total = max(1, item.totalDuration)
                    let progress = remaining <= 0 ? 1.0 : min(1.0, max(0.02, 1.0 - remaining / total))
                    TimeSlotProgressBar(
                        progress: CGFloat(progress),
                        color: itemColor,
                        height: 5,
                        showsKnob: false
                    )
                }
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
        ShortcutItem(keys: ["⌘", "1"], description: "切换至倒计时"),
        ShortcutItem(keys: ["⌘", "2"], description: "切换至番茄钟"),
        ShortcutItem(keys: ["⌘", "N"], description: "新建倒计时"),
        ShortcutItem(keys: ["⌘", "M"], description: "切换独立置顶禅模式悬浮窗"),
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
                        .background(Surface.field, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
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
                        .font(.system(size: 14, weight: .semibold))
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

            // 桌面壁纸背景模拟槽
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "#1E293B"), Color(hex: "#0F172A")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(maxWidth: .infinity, minHeight: 240)
                    .overlay {
                        // 柔光微光
                        Circle()
                            .fill((activeItem.map { Color(hex: $0.colorHex) } ?? store.accentPreset.color).opacity(0.18))
                            .frame(width: 180, height: 180)
                            .blur(radius: 40)
                    }

                renderedSimulatorWidget
                    .shadow(color: Color.black.opacity(0.35), radius: 18, y: 8)
            }
            .padding(.horizontal, Space.xl)

            Text("在桌面放置后，组件会跟随系统时钟秒级精准刷新。")
                .font(AppType.caption())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, Space.l)
    }

    @ViewBuilder
    private var renderedSimulatorWidget: some View {
        let item = activeItem
        let accent = item.map { Color(hex: $0.colorHex) } ?? store.accentPreset.color
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
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let rem = item?.remaining(at: context.date) ?? 3600
                    Text(rem > 0 ? "\(max(0, Int(rem / 86400))) 天" : "已到达")
                        .font(AppType.timer(24))
                        .foregroundStyle(accent)
                }
            }
            .padding(16)
            .frame(width: 155, height: 155)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))

        case .medium:
            HStack(spacing: 16) {
                ZStack {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let rem = item?.remaining(at: context.date) ?? 3600
                        let total = max(1, item?.totalDuration ?? 3600)
                        let prog = CGFloat(rem <= 0 ? 1.0 : min(1.0, max(0.02, 1.0 - rem / total)))
                        TimeSlotRing(progress: prog, color: accent, lineWidth: 8, showsGlow: true)
                    }
                    .frame(width: 90, height: 90)

                    Image(systemName: "timer")
                        .font(.system(size: 24))
                        .foregroundStyle(accent)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        BrandMark(size: 16)
                        Text(title)
                            .font(AppType.ui(14, .semibold))
                            .lineLimit(1)
                    }
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let rem = item?.remaining(at: context.date) ?? 3600
                        let d = max(0, Int(rem / 86400))
                        let h = (Int(rem) % 86400) / 3600
                        Text(rem > 0 ? "\(d)天 \(h)小时" : "目标达成")
                            .font(AppType.timer(24))
                            .monospacedDigit()
                            .foregroundStyle(accent)
                    }
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
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let rem = item?.remaining(at: context.date) ?? 3600
                            let total = max(1, item?.totalDuration ?? 3600)
                            let prog = CGFloat(rem <= 0 ? 1.0 : min(1.0, max(0.02, 1.0 - rem / total)))
                            TimeSlotRing(progress: prog, color: accent, lineWidth: 10, showsGlow: true)
                        }
                        .frame(width: 100, height: 100)

                        Image(systemName: "timer")
                            .font(.system(size: 28))
                            .foregroundStyle(accent)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let rem = item?.remaining(at: context.date) ?? 3600
                            let d = max(0, Int(rem / 86400))
                            let h = (Int(rem) % 86400) / 3600
                            let m = (Int(rem) % 3600) / 60
                            Text(rem > 0 ? "\(d)天 \(h):\(String(format: "%02d", m))" : "已到达")
                                .font(AppType.timer(26))
                                .monospacedDigit()
                                .foregroundStyle(accent)
                        }
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
                .font(.system(size: 12, weight: .semibold))
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
        Button(action: action) {
            HStack(spacing: 10) {
                // Apple Reminders 风格的色彩圆形徽标
                ZStack {
                    Circle()
                        .fill(accent.opacity(isSelected ? 0.24 : 0.14))
                        .frame(width: 28, height: 28)

                    Image(systemName: item.isPaused ? "pause.fill" : (item.isPinned ? "pin.fill" : "calendar"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(accent)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(item.title)
                            .font(AppType.ui(13, isSelected ? .semibold : .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if item.isPinned {
                            Image(systemName: "rectangle.3.group.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(accent.opacity(0.85))
                        }
                    }

                    // 每行只让即将到期（<24h）的项目按秒刷新
                    let remaining = item.remaining(at: Date())
                    if item.isPaused || remaining > 86400 {
                        rowProgress(remaining)
                    } else {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            rowProgress(item.remaining(at: context.date))
                        }
                    }
                }

                Spacer(minLength: 4)

                // 右侧 Apple 风格数字读数
                let remaining = item.remaining(at: Date())
                let isUrgent = remaining > 0 && remaining < 86400 && !item.isPaused
                VStack(alignment: .trailing, spacing: 2) {
                    Text(remaining > 0 ? (remaining >= 86400 ? "\(max(1, Int(remaining / 86400))) 天" : formatCompact(remaining)) : "已到达")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(remaining <= 0 ? Color.secondary : (isUrgent ? Color.orange : accent))

                    if isUrgent {
                        Text("今天")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.orange)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? accent.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? accent.opacity(0.24) : Color.clear, lineWidth: 0.8)
            )
        }
        .buttonStyle(TimeSlotPressableStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(
            item.isPaused
                ? "已暂停，\(remainingTextValue(item.remaining(at: Date())))"
                : remainingTextValue(item.remaining(at: Date()))
        )
    }

    private func rowProgress(_ remaining: TimeInterval) -> some View {
        let total = max(1, item.totalDuration)
        let prog = remaining <= 0 ? 1.0 : min(1.0, max(0.0, 1.0 - remaining / total))
        return ProgressView(value: prog)
            .progressViewStyle(.linear)
            .tint(accent)
            .frame(width: 95)
            .scaleEffect(x: 1, y: 0.6, anchor: .leading)
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

    @ViewBuilder
    var body: some View {
        if item.isPaused {
            card(remaining: item.remaining(at: Date()))
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

                    // 模块化时间单元卡片展示
                    if isDone {
                        HStack(spacing: Space.m) {
                            Image(systemName: "flag.checkered.circle.fill")
                                .font(.system(size: 38))
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
                        .fill(accent.opacity(0.12))
                        .frame(width: 54, height: 54)
                    Image(systemName: isDone ? "checkmark.circle.fill" : (item.isPaused ? "pause.fill" : "timer"))
                        .font(AppType.ui(Typo.icon, .medium))
                        .foregroundStyle(accent)
                        .symbolEffect(.pulse, isActive: !isDone && !item.isPaused)
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
                    showsMilestones: true
                )
            }

            HStack {
                Label(beijingDateString(item.targetDate, dateStyle: .complete, timeStyle: .shortened), systemImage: "calendar")
                    .font(AppType.ui(Typo.footnote, .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("北京时间 (UTC+8)")
                    .font(AppType.caption())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(Space.xl)
        .overlay {
            ConfettiEffectView(isActive: isDone)
        }
        .cardSurface(
            cornerRadius: Radius.large,
            borderOpacity: 0.09,
            shadowRadius: 14,
            shadowY: 4
        )
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

            VStack(spacing: Space.m) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = item.remaining(at: context.date)
                    let total = max(1, item.totalDuration)
                    let elapsed = max(0, total - remaining)
                    let elapsedDays = Int(elapsed / 86400)
                    let remainingDays = Int(ceil(remaining / 86400))

                    HStack {
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
                                .foregroundStyle(accent)
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
            .padding(Space.m)
            .background(Surface.nested, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
        }
    }
}

struct QuickActionButton: View {
    let title: String
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(AppType.ui(Typo.footnote, .medium))
                .padding(.horizontal, Space.m)
                .padding(.vertical, Space.s)
        }
        .buttonStyle(.bordered)
        .tint(tint)
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
    @State private var title: String
    @State private var targetDate: Date
    @State private var colorHex: String
    @FocusState private var titleFocused: Bool

    private let colorOptions: [(name: String, hex: String)] = [
        ("青绿", "#2C8C7C"),
        ("珊瑚", "#D86F52"),
        ("靛蓝", "#5A78B8"),
        ("琥珀", "#B07A3A"),
        ("紫罗兰", "#7B5EA7"),
        ("森林", "#4C9A5A")
    ]

    init(mode: Mode, onSave: @escaping (String, Date, String) -> Void) {
        self.mode = mode
        self.onSave = onSave
        switch mode {
        case .add:
            _title = State(initialValue: "")
            _targetDate = State(initialValue: beijingCalendar.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3600))
            _colorHex = State(initialValue: "#2C8C7C")
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
                                        .fill(Color(hex: option.hex))
                                        .frame(width: 28, height: 28)
                                        .overlay {
                                            Circle()
                                                .stroke(
                                                    Color.primary.opacity(colorHex == option.hex ? 0.82 : 0.08),
                                                    lineWidth: colorHex == option.hex ? 2 : 1
                                                )
                                                .padding(colorHex == option.hex ? -4 : 0)
                                        }
                                        .overlay {
                                            if colorHex == option.hex {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 10, weight: .bold))
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
                            .accessibilityValue(colorHex == option.hex ? "已选中" : "未选中")
                        }
                    }
                }

                // 实时预览卡片
                HStack(spacing: Space.m) {
                    Circle()
                        .fill(Color(hex: colorHex))
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
                        .foregroundStyle(Color(hex: colorHex))
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
                    .tint(Color(hex: colorHex))
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

    private var modeTitle: String {
        switch mode {
        case .add: return "新建倒计时"
        case .edit: return "编辑倒计时"
        }
    }
}
