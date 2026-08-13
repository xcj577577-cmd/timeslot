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


struct ContentView: View {
    @ObservedObject var store: CountdownStore
    @State private var showingAdd = false
    @State private var showingEdit = false
    @State private var showingWidgetHelp = false
    @State private var pendingDelete: CountdownItem?
    @State private var searchText = ""
    @State private var selectedSection: TimeBookSection = .countdown
    @FocusState private var searchFieldFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var accent: Color { store.accentPreset.color }
    private var stopwatchColor: Color { store.accentPreset.color }

    var filteredItems: [CountdownItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.items }
        return store.items.filter { $0.title.localizedCaseInsensitiveContains(query) }
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
            if let action = store.undoableAction {
                UndoBanner(action: action, accent: accent) {
                    store.undoLastAction()
                }
                .padding(.trailing, Space.xl)
                .padding(.bottom, Space.xl)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: store.undoableAction)
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
                    VStack(alignment: .leading, spacing: Space.xs) {
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
                    .help("新建倒计时")
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
            .padding(.bottom, Space.l)

            if selectedSection == .countdown {
                HStack(spacing: Space.s) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("搜索倒计时", text: $searchText)
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
                .padding(.bottom, Space.m)

                HStack {
                    Text(searchText.isEmpty ? "全部倒计时" : "搜索结果")
                        .font(AppType.caption(weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(filteredItems.count)")
                        .font(AppType.caption(weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(accent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(accent.opacity(0.11), in: Capsule())
                }
                .padding(.horizontal, Space.xl)
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
                    Label("桌面小组件", systemImage: "macwindow.on.rectangle")
                        .font(AppType.ui(Typo.footnote, .medium))
                        .tracking(Tracking.label)
                        .foregroundStyle(.secondary)
                    Text("独立倒计时组件沿用当前固定目标；如果要让多个组件显示不同目标，请添加“时隙 · 自定义”，再为每个组件分别选择倒计时。")
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
            .contentShape(RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
            .accessibilityLabel("设置")
            .accessibilityIdentifier("timeslot.settings.open")
            .accessibilityValue(selectedSection == .settings ? "已选中" : "未选中")
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
        let phaseColor = Color(hex: state.phase.colorHex)
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
                    (store.selectedItem.map { Color(hex: $0.colorHex).opacity(0.05) } ?? Color.clear),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .center
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("倒计时详情")
                        .font(AppType.caption(Typo.body, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(store.selectedItem?.title ?? "选择一个倒计时")
                        .font(AppType.pageTitle())
                        .tracking(Tracking.pageTitle)
                        .lineLimit(1)
                }
                Spacer()
                if let selected = store.selectedItem {
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

            if let selected = store.selectedItem {
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
                            QuickActionButton(title: "添加小组件指南", icon: "questionmark.circle", tint: accent) {
                                showingWidgetHelp = true
                            }
                            QuickActionButton(title: selected.isPaused ? "继续" : "暂停", icon: selected.isPaused ? "play.fill" : "pause.fill", tint: selected.isPaused ? accent : Color.secondary) {
                                store.togglePause(selected)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
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

    private func infoSection(_ item: CountdownItem) -> some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Text("目标信息")
                .font(AppType.ui(Typo.body, .medium))
                .tracking(Tracking.heading)
                .foregroundStyle(.secondary)
            HStack(spacing: 0) {
                InfoCell(label: "目标时间", value: beijingDateString(item.targetDate, dateStyle: .abbreviated, timeStyle: .shortened), icon: "calendar")
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
                InfoCell(label: "桌面小组件", value: item.isPinned ? "当前内容" : "未选用", icon: item.isPinned ? "rectangle.3.group.fill" : "rectangle.3.group")
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

    /// macOS 的 segmented Picker 会在自身更新周期里回写 selection。
    /// 直接绑定 @Published 会触发 “Publishing changes from within view updates”。
    /// 延迟到下一轮主队列再更新 Store，既保留原生 Picker，也消除未定义行为。
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

    private var accent: Color { store.accentPreset.color }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.m) {
                BrandMark(size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("把时隙放到桌面")
                        .font(AppType.title(Typo.sheetTitle))
                    Text("添加一次，之后的内容会自动同步")
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

            Divider()

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
                        detail: "添加“时隙 · 自定义”后，右键每个组件选择“编辑小组件”，即可绑定不同倒计时；目标被删除时会自动回退到当前固定项。",
                        accent: accent
                    )
                }

                VStack(alignment: .leading, spacing: Space.m) {
                    Text("可添加的组件")
                        .font(AppType.ui(Typo.footnote, .medium))
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: Space.s
                    ) {
                        WidgetTypeTile(title: "倒计时", icon: "calendar.badge.clock", accent: accent)
                        WidgetTypeTile(title: "自定义", icon: "slider.horizontal.3", accent: accent)
                        WidgetTypeTile(title: "番茄钟", icon: "timer", accent: accent)
                        WidgetTypeTile(title: "正计时", icon: "stopwatch.fill", accent: accent)
                        WidgetTypeTile(title: "本周专注", icon: "target", accent: accent)
                    }
                    Text("另有组合总览和可编辑版本；自定义版本可让每个小组件绑定不同倒计时。")
                        .font(AppType.caption())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(Space.xl)

            Divider()

            HStack {
                Button("立即刷新") {
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
        .frame(width: 520)
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
            HStack(spacing: Space.m) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(accent)
                    .frame(width: 4, height: 37)
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(item.title)
                        .font(AppType.ui(Typo.body, .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    // 每行只让这一小段跟着秒走；暂停中的条目读数不变，连计时器都不用起。
                    if item.isPaused {
                        rowProgress(item.remaining(at: Date()))
                    } else {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            rowProgress(item.remaining(at: context.date))
                        }
                    }
                }
                Spacer(minLength: 4)
                if item.isPinned {
                    Image(systemName: "rectangle.3.group.fill")
                        .font(AppType.caption())
                        .foregroundStyle(accent)
                }
            }
            .padding(.horizontal, Space.m)
            .padding(.vertical, Space.s)
            .background(isSelected ? accent.opacity(0.14) : Color.clear)
            .overlay {
                RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                    .stroke(isSelected ? accent.opacity(0.26) : Color.clear, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.small))
        }
        .buttonStyle(TimeSlotPressableStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(
            item.isPaused
                ? "已暂停，\(remainingTextValue(item.remaining(at: Date())))"
                : remainingTextValue(item.remaining(at: Date()))
        )
    }

    private func remainingText(_ remaining: TimeInterval) -> some View {
        Text(remaining > 0 ? formatCompact(remaining) : "已结束")
            .font(AppType.ui(Typo.footnote, .medium))
            .monospacedDigit()
            .foregroundStyle(remaining > 0 ? Color.secondary : Color.red)
    }

    private func rowProgress(_ remaining: TimeInterval) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            remainingText(remaining)
            TimeSlotProgressBar(
                progress: remaining <= 0 ? 1 : min(1, max(0, 1 - remaining / max(1, item.totalDuration))),
                color: accent,
                height: 4,
                showsKnob: false
            )
            .frame(width: 132, alignment: .leading)
        }
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

struct CountdownHero: View {
    let item: CountdownItem
    let accent: Color

    @ViewBuilder
    var body: some View {
        // 暂停中读数是固定的，不必起计时器；只有走着的倒计时才按秒重画这张卡片。
        if item.isPaused {
            card(remaining: item.remaining(at: Date()))
        } else {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                card(remaining: item.remaining(at: context.date))
            }
        }
    }

    private func card(remaining: TimeInterval) -> some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Space.s) {
                    Text(item.isPaused ? "倒计时已暂停" : (remaining > 0 ? "距离目标还有" : "目标已到达"))
                        .font(AppType.ui(Typo.body, .medium))
                        .foregroundStyle(.secondary)
                    remainingDisplay(remaining)
                        .font(AppType.timer(Typo.timerLarge))
                        .tracking(Tracking.timer)
                        .monospacedDigit()
                        .foregroundStyle(accent)
                }
                Spacer()
                Image(systemName: remaining > 0 ? "timer" : "checkmark.circle.fill")
                    .font(AppType.ui(Typo.icon, .medium))
                    .foregroundStyle(accent.opacity(0.75))
                    .padding(Space.m)
                    .background(accent.opacity(0.12))
                    .clipShape(Circle())
                    .symbolEffect(.pulse, isActive: remaining > 0 && !item.isPaused)
            }

            TimeSlotProgressBar(
                progress: progressValue(remaining),
                color: accent,
                height: 10,
                showsKnob: true
            )

            HStack {
                Label(beijingDateString(item.targetDate, dateStyle: .complete, timeStyle: .shortened), systemImage: "calendar")
                    .font(AppType.ui(Typo.footnote, .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(item.isPaused ? "已暂停" : (progressValue(remaining) >= 1 ? "已完成" : "进行中"))
                    .font(AppType.ui(Typo.footnote, .medium))
                    .foregroundStyle(accent)
                    .padding(.horizontal, Space.s)
                    .padding(.vertical, Space.xs)
                    .background(accent.opacity(0.10), in: Capsule())
            }
        }
        .padding(Space.xl)
        .cardSurface(
            cornerRadius: Radius.large,
            borderOpacity: 0.09,
            shadowRadius: 14,
            shadowY: 4
        )
    }

    private func remainingText(_ remaining: TimeInterval) -> String {
        if remaining <= 0 { return "00:00:00" }
        let total = Int(ceil(remaining))
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if days > 0 { return String(format: "%02d天 %02d:%02d:%02d", days, hours, minutes, seconds) }
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    /// 最后一小时交给系统 timer 样式：与应用内番茄钟、桌面小组件同一套时钟，
    /// 秒级跳动完全一致，不再依赖 TimelineView 的回调时延。
    @ViewBuilder
    private func remainingDisplay(_ remaining: TimeInterval) -> some View {
        if !item.isPaused, remaining > 0, remaining < 86400 {
            Text(item.targetDate, style: .timer)
        } else {
            Text(remainingText(remaining))
        }
    }

    private func progressValue(_ remaining: TimeInterval) -> CGFloat {
        let span = max(item.totalDuration, 1)
        return remaining <= 0 ? 1 : min(1, max(0.04, 1 - remaining / span))
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
        case oneWeek
        case oneMonth

        var id: String { rawValue }

        var title: String {
            switch self {
            case .oneHour: return "1 小时后"
            case .tomorrow: return "明天此时"
            case .oneWeek: return "7 天后"
            case .oneMonth: return "30 天后"
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
            case .oneWeek:
                return beijingCalendar.date(byAdding: .day, value: 7, to: now)
                    ?? now.addingTimeInterval(7 * 86_400)
            case .oneMonth:
                return beijingCalendar.date(byAdding: .day, value: 30, to: now)
                    ?? now.addingTimeInterval(30 * 86_400)
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
                    TextField("例如：项目演示、旅行出发", text: $title)
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

                    HStack(spacing: Space.s) {
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
        .frame(width: 520)
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
