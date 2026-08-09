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
                        colors: [Color(hex: "#091A2C"), Color(hex: "#0E3836"), Color(hex: "#145754")],
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

            // 左段：时间条带被斜切后上移
            RoundedRectangle(cornerRadius: size * 0.052, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "#8CE4D0"), Color(hex: "#38BDA6")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size * 0.295, height: size * 0.115)
                .offset(x: -size * 0.1825, y: -size * 0.048)

            // 右段：斜切后下移
            RoundedRectangle(cornerRadius: size * 0.052, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "#8CE4D0"), Color(hex: "#38BDA6")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size * 0.295, height: size * 0.115)
                .offset(x: size * 0.1825, y: size * 0.048)

            // 金色斜缝：两段之间的“时隙”
            Path { path in
                let yTop = size * 0.4425
                let off = size * 0.048
                let bandH = size * 0.115
                path.move(to: CGPoint(x: size * 0.465, y: yTop - off))
                path.addLine(to: CGPoint(x: size * 0.535, y: yTop + off))
                path.addLine(to: CGPoint(x: size * 0.535, y: yTop + off + bandH))
                path.addLine(to: CGPoint(x: size * 0.465, y: yTop - off + bandH))
                path.closeSubpath()
            }
            .fill(
                LinearGradient(
                    colors: [Color(hex: "#EDD498"), Color(hex: "#C79A47")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )

            // 右下金色刻度点：非对称点缀
            Circle()
                .fill(Color(hex: "#EDD498").opacity(0.95))
                .frame(width: size * 0.034, height: size * 0.034)
                .offset(x: size * 0.27, y: size * 0.20)
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

    private var accent: Color { store.accentPreset.color }
    private var stopwatchColor: Color { store.accentPreset.color }

    var filteredItems: [CountdownItem] {
        guard !searchText.isEmpty else { return store.items }
        return store.items.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
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
        .onReceive(NotificationCenter.default.publisher(for: .newCountdownRequested)) { _ in
            showingAdd = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToCountdownRequested)) { _ in
            withAnimation(.easeOut(duration: 0.18)) {
                selectedSection = .countdown
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToPomodoroRequested)) { _ in
            withAnimation(.easeOut(duration: 0.18)) {
                selectedSection = .pomodoro
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showWidgetHelpRequested)) { _ in
            showingWidgetHelp = true
        }
        .alert("小组件已自动同步", isPresented: $showingWidgetHelp) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("从今天起不再需要手动同步：应用里的倒计时、番茄钟、正计时和周目标变化后，桌面小组件会自动跟随，最长 1 分钟自检一次。如果还没添加过小组件，在 Mac 桌面空白处右键选择“编辑小组件”，搜索“时隙”即可分别添加倒计时、正计时、番茄钟或本周专注目标；组合版和可编辑版也会保留。")
            .lineSpacing(3)
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
            Text("删除后无法恢复。桌面小组件会自动切换显示其他倒计时。")
                .lineSpacing(2.5)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: Space.m) {
                    BrandMark(size: 30)
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
                }
                .padding(.horizontal, Space.m)
                .padding(.vertical, Space.s)
                .background(Surface.field)
                .clipShape(RoundedRectangle(cornerRadius: Radius.small))
                .padding(.horizontal, Space.l)
                .padding(.bottom, Space.l)

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
                    Text("先选择要固定的倒计时，再从 macOS 小组件库单独添加倒计时、正计时、番茄钟或本周专注目标。")
                        .font(AppType.ui(Typo.footnote))
                        .lineSpacing(2.5)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    widgetModePicker
                    Button {
                        guard let item = store.selectedItem else { return }
                        pinToDesktop(item)
                    } label: {
                        Label("同步到桌面", systemImage: "rectangle.3.group")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(accent)
                    .disabled(store.selectedItem == nil)
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
                withAnimation(.easeOut(duration: 0.18)) {
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
            .accessibilityValue(selectedSection == .settings ? "已选中" : "未选中")
            .padding(.horizontal, Space.m)
            .padding(.bottom, Space.m)
        }
        .frame(width: 248)
        .background(Surface.sidebar)
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
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.0.0"
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
                    Label("同步到桌面", systemImage: "rectangle.3.group")
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
        .transition(.opacity.combined(with: .scale(scale: 0.985)))
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
                    Button(role: .destructive) {
                        pendingDelete = selected
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("删除倒计时")
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
                            QuickActionButton(title: "同步到桌面", icon: "rectangle.3.group", tint: accent) {
                                pinToDesktop(selected)
                            }
                            QuickActionButton(title: selected.isPinned ? "桌面组件内容" : "设为桌面组件", icon: selected.isPinned ? "checkmark.circle.fill" : "rectangle.on.rectangle", tint: Color(hex: selected.colorHex)) {
                                store.selectForDesktopWidget(selected)
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
                InfoCell(label: "桌面组件", value: item.isPinned ? "当前内容" : "未选用", icon: item.isPinned ? "rectangle.3.group.fill" : "rectangle.3.group")
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

    let mode: Mode
    let onSave: (String, Date, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var targetDate: Date
    @State private var colorHex: String

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
        VStack(alignment: .leading, spacing: Space.xl) {
            HStack {
                Text(modeTitle)
                    .font(AppType.title(Typo.sheetTitle))
                        .tracking(Tracking.heading)
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            VStack(alignment: .leading, spacing: Space.s) {
                Text("标题")
                    .font(AppType.ui(Typo.footnote, .medium))
                TextField("例如：项目演示、旅行出发", text: $title)
                    .textFieldStyle(.roundedBorder)
                Text("名称会显示在侧栏和桌面小组件中")
                    .font(AppType.caption())
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: Space.s) {
                Text("目标时间")
                    .font(AppType.ui(Typo.footnote, .medium))
                DatePicker("", selection: $targetDate, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .datePickerStyle(.graphical)
            }

            VStack(alignment: .leading, spacing: Space.s) {
                Text("颜色")
                    .font(AppType.ui(Typo.footnote, .medium))
                HStack(spacing: Space.m) {
                    ForEach(["#2C8C7C", "#D86F52", "#5A78B8", "#B07A3A"], id: \.self) { hex in
                        Button {
                            colorHex = hex
                        } label: {
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 24, height: 24)
                                .overlay {
                                    Circle().stroke(Color.primary.opacity(colorHex == hex ? 0.85 : 0), lineWidth: 2)
                                        .padding(-3)
                                }
                                .contentShape(Circle())
                        }
                        .buttonStyle(TimeSlotPressableStyle())
                        .accessibilityLabel("选择颜色")
                        .accessibilityValue(colorHex == hex ? "已选中" : "")
                    }
                }
            }

            HStack {
                Spacer()
                Button("保存") {
                    onSave(title.trimmingCharacters(in: .whitespacesAndNewlines), targetDate, colorHex)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: colorHex))
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(Space.xl)
        .frame(width: 390)
    }

    private var modeTitle: String {
        switch mode {
        case .add: return "新建倒计时"
        case .edit: return "编辑倒计时"
        }
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
