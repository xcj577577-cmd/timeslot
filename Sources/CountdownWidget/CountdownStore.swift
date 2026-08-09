import AppKit
import Combine
import SwiftUI
import WidgetKit
import UserNotifications

@MainActor
final class CountdownStore: ObservableObject {
    @Published var items: [CountdownItem] {
        didSet { save() }
    }
    @Published var selectedID: UUID? {
        didSet {
            countdownDefaults.set(selectedID?.uuidString, forKey: "selectedCountdownID")
        }
    }
    @Published var pomodoro: PomodoroState {
        didSet { savePomodoro() }
    }
    @Published var pomodoroHistory: [PomodoroSessionRecord] {
        didSet { savePomodoroHistory() }
    }
    @Published var pomodoroTasks: [PomodoroTask] {
        didSet { savePomodoroTasks() }
    }
    @Published var widgetDisplayMode: WidgetDisplayMode {
        didSet {
            CountdownStore.saveSharedString(widgetDisplayMode.rawValue, forKey: widgetDisplayModeKey)
            persistWidgetStateFile()
            reloadDesktopWidgetNow()
        }
    }
    @Published var widgetTimeUnit: String {
        didSet {
            CountdownStore.saveSharedString(widgetTimeUnit, forKey: widgetTimeUnitKey)
            persistWidgetStateFile()
            reloadDesktopWidgetNow()
        }
    }
    @Published var accentPreset: ColorPreset {
        didSet {
            guard accentPreset != oldValue else { return }
            countdownDefaults.set(accentPreset.rawValue, forKey: accentPresetKey)
        }
    }
    @Published var appearanceMode: AppAppearance {
        didSet {
            guard appearanceMode != oldValue else { return }
            countdownDefaults.set(appearanceMode.rawValue, forKey: appearanceModeKey)
            NSApp.appearance = appearanceMode.nsAppearance
        }
    }

    private var timerCancellable: AnyCancellable?
    private var widgetReloadTask: DispatchWorkItem?
    /// 共享状态文件位于 App Group 容器中，系统偶尔会在启动时短暂等待文件协调。
    /// 不能让这次 I/O 卡住主线程；串行队列同时保证多次状态变化按顺序落盘。
    private let widgetStateWriteQueue = DispatchQueue(
        label: "com.xianz.countdownwidget.widget-state-write",
        qos: .utility
    )
    /// 上一次小组件健康检查（兜底同步）的时间。按真实墙钟判断而不是按 tick 计数，
    /// 这样系统睡眠唤醒后也能立刻触发一次刷新，不会错过睡眠期间的累计变化。
    private var lastWidgetHealthReload = Date()
    /// 已触发过完成反馈的倒计时，避免同一目标每秒重复响铃。
    private var countdownCompletionPlayed: Set<UUID> = []
    /// 通知权限是否已授予；授予后由系统通知负责响铃，未授予时应用内播放提示音兜底。
    private var notificationPermissionGranted = false
    /// 已排入系统队列的番茄钟阶段通知 id，暂停/重置/停顿时按 id 精确取消，不误删倒计时通知。
    private var pendingPomodoroNotificationIDs: Set<String> = []
    private static let sharedDefaultsName = "4FKFDX48HX.com.xianz.countdownwidget.shared"
    private let storageKey = "countdownItems"
    private let pomodoroStorageKey = "pomodoroState"
    private let pomodoroHistoryStorageKey = "pomodoroHistory"
    private let pomodoroTasksStorageKey = "pomodoroTasks"
    private let widgetDisplayModeKey = "widgetDisplayMode"
    private let widgetTimeUnitKey = "widgetTimeUnit"
    private let accentPresetKey = "accentPreset"
    private let appearanceModeKey = "appearanceMode"
    /// 不足 10 秒的专注/阶段没有统计意义，不写入历史，启动时也会清掉旧数据。
    private static let minimumMeaningfulSessionDuration: TimeInterval = 10
    private static let widgetKinds = [
        "CountdownDesktopWidget",
        "CountdownDesktopWidgetConfig",
        "CountdownOnlyWidget",
        "StopwatchOnlyWidget",
        "PomodoroOnlyWidget",
        "WeeklyFocusGoalWidget"
    ]

    private struct WidgetStateFile: Codable {
        let items: [CountdownItem]
        let pomodoro: PomodoroState
        let pomodoroHistory: [PomodoroSessionRecord]?
        let displayMode: String
        let timeUnit: String
        let updatedAt: Date
    }

    /// 直接写给小组件的状态文件。UserDefaults 的落盘由 cfprefsd 异步控制，
    /// 应用刚改完状态时扩展进程可能还读到旧值；这份文件是原子的、立即可见的。
    private static var sharedStateFileURL: URL? {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Self.sharedDefaultsName
        ) else { return nil }
        return container
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent("widget-state.json")
    }

    private var widgetStateURL: URL? {
        Self.sharedStateFileURL
    }

    private static func loadWidgetStateFile() -> WidgetStateFile? {
        guard let url = sharedStateFileURL,
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetStateFile.self, from: data)
    }

    private func persistWidgetStateFile() {
        guard let url = widgetStateURL else { return }
        let state = WidgetStateFile(
            items: items,
            pomodoro: pomodoro,
            pomodoroHistory: pomodoroHistory,
            displayMode: widgetDisplayMode.rawValue,
            timeUnit: widgetTimeUnit,
            updatedAt: Date()
        )
        guard let data = try? JSONEncoder().encode(state) else { return }
        let directory = url.deletingLastPathComponent()
        let widgetKinds = Self.widgetKinds
        widgetStateWriteQueue.async {
            var didWrite = false
            do {
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
                try data.write(to: url, options: .atomic)
                didWrite = true
            } catch {
                // 写文件失败时仍走 UserDefaults 与 reload 兜底，不阻塞计时。
            }
            guard didWrite else { return }
            // 只有原子文件写完后才请求 WidgetKit 重建，避免扩展先读到旧快照。
            for kind in widgetKinds {
                WidgetCenter.shared.reloadTimelines(ofKind: kind)
            }
        }
    }

    private static func loadSharedData(forKey key: String) -> Data? {
        if let data = countdownDefaults.data(forKey: key) {
            return data
        }
        return UserDefaults.standard.data(forKey: key)
    }

    private static func loadSharedString(forKey key: String) -> String? {
        return countdownDefaults.string(forKey: key) ?? UserDefaults.standard.string(forKey: key)
    }

    private static func saveSharedData(_ data: Data, forKey key: String) {
        countdownDefaults.set(data, forKey: key)
    }

    private static func saveSharedString(_ value: String, forKey key: String) {
        countdownDefaults.set(value, forKey: key)
    }

    // MARK: - 通知与声音开关

    var notificationsEnabled: Bool {
        get { countdownDefaults.object(forKey: "enableNotifications") as? Bool ?? true }
        set {
            countdownDefaults.set(newValue, forKey: "enableNotifications")
            if newValue {
                requestNotificationPermissionIfNeeded()
            } else {
                cancelAllScheduledNotifications()
            }
        }
    }

    var soundsEnabled: Bool {
        get { countdownDefaults.object(forKey: "enableSounds") as? Bool ?? true }
        set { countdownDefaults.set(newValue, forKey: "enableSounds") }
    }

    func setNotificationsEnabled(_ enabled: Bool) {
        notificationsEnabled = enabled
    }

    func setSoundsEnabled(_ enabled: Bool) {
        soundsEnabled = enabled
    }

    private static func defaultCountdownItems() -> [CountdownItem] {
        [
            CountdownItem(
                title: "今天的专注时段",
                targetDate: beijingCalendar.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3600),
                colorHex: "#2C8C7C",
                isPinned: true
            ),
            CountdownItem(
                title: "产品发布",
                targetDate: beijingCalendar.date(byAdding: .day, value: 3, to: Date()) ?? Date().addingTimeInterval(259200),
                colorHex: "#D86F52"
            )
        ]
    }

    init() {
        let sharedWidgetState = Self.loadWidgetStateFile()
        let shouldRestoreRunningPomodoro = sharedWidgetState?.pomodoro.isRunning == true
            || sharedWidgetState?.pomodoro.isStopwatchActive == true
        // cfprefsd 可能保留旧缓存；启动前先同步一次，避免把仍在运行的番茄钟读成旧状态。
        if !shouldRestoreRunningPomodoro {
            countdownDefaults.synchronize()
        }
        var loadedItems: [CountdownItem]
        if let data = CountdownStore.loadSharedData(forKey: storageKey) {
            do {
                let saved = try JSONDecoder().decode([CountdownItem].self, from: data)
                loadedItems = saved.isEmpty ? Self.defaultCountdownItems() : saved
            } catch {
                Self.preserveCorruptedDataIfNeeded(data, forKey: storageKey)
                loadedItems = Self.defaultCountdownItems()
            }
        } else {
            loadedItems = Self.defaultCountdownItems()
        }
        // 桌面小组件取的是第一个 isPinned 的条目，所以这里保证有且只有一个被选中。
        // 已有数据两种都可能坏：旧版默认值 true 会让多条同时选中（界面上每条都显示
        // 「当前内容」），更旧的数据又完全没有这个字段、回落成一条都没选。
        if let pinnedIndex = loadedItems.firstIndex(where: { $0.isPinned }) {
            for index in loadedItems.indices where index != pinnedIndex {
                loadedItems[index].isPinned = false
            }
        } else if !loadedItems.isEmpty {
            loadedItems[0].isPinned = true
        }
        items = loadedItems
        let loadedPomodoroFromDefaults: PomodoroState
        if let data = CountdownStore.loadSharedData(forKey: pomodoroStorageKey) {
            do {
                loadedPomodoroFromDefaults = try JSONDecoder().decode(PomodoroState.self, from: data)
            } catch {
                Self.preserveCorruptedDataIfNeeded(data, forKey: pomodoroStorageKey)
                loadedPomodoroFromDefaults = PomodoroState()
            }
        } else {
            loadedPomodoroFromDefaults = PomodoroState()
        }
        let loadedPomodoro = shouldRestoreRunningPomodoro
            ? sharedWidgetState!.pomodoro
            : loadedPomodoroFromDefaults
        pomodoro = loadedPomodoro
        if let data = CountdownStore.loadSharedData(forKey: pomodoroHistoryStorageKey) {
            do {
                let saved = try JSONDecoder().decode([PomodoroSessionRecord].self, from: data)
                pomodoroHistory = saved.filter {
                    $0.actualDuration >= Self.minimumMeaningfulSessionDuration
                }
            } catch {
                Self.preserveCorruptedDataIfNeeded(data, forKey: pomodoroHistoryStorageKey)
                pomodoroHistory = []
            }
        } else {
            pomodoroHistory = []
        }
        let currentTaskTitle = PomodoroTaskPalette.normalized(loadedPomodoro.taskTitle)
        let currentTask = PomodoroTask(title: currentTaskTitle)
        let loadedTasks: [PomodoroTask]
        if let data = CountdownStore.loadSharedData(forKey: pomodoroTasksStorageKey) {
            let saved: [PomodoroTask]
            do {
                saved = try JSONDecoder().decode([PomodoroTask].self, from: data)
            } catch {
                Self.preserveCorruptedDataIfNeeded(data, forKey: pomodoroTasksStorageKey)
                saved = []
            }
            if saved.contains(where: {
                PomodoroTaskPalette.normalized($0.title)
                    .localizedCaseInsensitiveCompare(currentTaskTitle) == .orderedSame
            }) {
                loadedTasks = saved
            } else {
                loadedTasks = [currentTask] + saved
            }
        } else {
            loadedTasks = [currentTask]
        }
        // 旧数据没有 colorHex，这里按列表顺序补齐，前 8 个任务各拿一种颜色。
        pomodoroTasks = CountdownStore.withAssignedColors(loadedTasks)
        widgetDisplayMode = CountdownStore.loadSharedString(forKey: widgetDisplayModeKey)
            .flatMap(WidgetDisplayMode.init(rawValue:)) ?? .both
        widgetTimeUnit = CountdownStore.loadSharedString(forKey: widgetTimeUnitKey) ?? "days"
        let storedID = countdownDefaults.string(forKey: "selectedCountdownID").flatMap(UUID.init(uuidString:))
        accentPreset = ColorPreset(rawValue: countdownDefaults.string(forKey: accentPresetKey) ?? "") ?? .teal
        appearanceMode = AppAppearance(rawValue: countdownDefaults.string(forKey: appearanceModeKey) ?? "") ?? .system
        NSApp.appearance = appearanceMode.nsAppearance
        selectedID = storedID.flatMap { id in items.contains(where: { $0.id == id }) ? id : nil } ?? items.first?.id

        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                // 这个 tick 只用来判定阶段是否结束，不再每秒发布状态。
                // 原来每秒 @Published 一次 currentDate，会让整个 ContentView（含
                // Swift Charts 图表和历史列表）重算重排，主线程被布局吃满。
                // 需要按秒走字的地方改用各自的 TimelineView。
                self?.handlePomodoroTick(at: Date())
                self?.checkCountdownCompletions(at: Date())
                // 兜底同步：即使扩展进程的刷新请求被系统合并或错过，
                // 应用只要开着，每 4 分钟也会主动让小组件重新读取一次状态。
                // 原来 55 秒一次会叠加到 WidgetKit 刷新预算里，改成低频单次以降低节流概率。
                if let self, Date().timeIntervalSince(self.lastWidgetHealthReload) >= 240 {
                    self.lastWidgetHealthReload = Date()
                    self.performWidgetReload()
                }
            }

        persistSharedStateWithoutWidgetReload()
        savePomodoroHistory()
        savePomodoroTasks()
        requestNotificationPermissionIfNeeded()
        rescheduleCountdownNotifications()
        // 启动后主动刷新一次桌面组件：系统可能仍保留着更新前启动的扩展进程，
        // 让组件尽早按最新共享数据重新生成，而不是继续展示旧快照。
        reloadDesktopWidgetNow()
    }

    var selectedItem: CountdownItem? {
        guard let selectedID else { return items.first }
        return items.first(where: { $0.id == selectedID }) ?? items.first
    }

    func add(title: String, targetDate: Date, colorHex: String) {
        // 只有在还没有任何条目占用桌面组件时才自动选中，避免新建的倒计时
        // 悄悄顶掉用户手动设定的桌面组件内容。
        let shouldPin = !items.contains(where: { $0.isPinned })
        let item = CountdownItem(
            title: title.isEmpty ? "未命名倒计时" : title,
            targetDate: targetDate,
            colorHex: colorHex,
            isPinned: shouldPin
        )
        items.insert(item, at: 0)
        selectedID = item.id
        rescheduleCountdownNotifications()
    }

    func update(_ item: CountdownItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = item
    }

    func applyEdit(to item: CountdownItem, title: String, targetDate: Date, colorHex: String) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        var updated = items[index]
        updated.title = title.isEmpty ? "未命名倒计时" : title
        updated.colorHex = colorHex
        if targetDate != updated.targetDate {
            // 改了目标时间就重新确定进度条的基准区间，否则进度仍按创建时的跨度计算。
            let now = Date()
            updated.targetDate = targetDate
            updated.totalDuration = max(1, targetDate.timeIntervalSince(now))
            if updated.pausedRemaining != nil {
                // 暂停中的条目走 pausedRemaining，不同步的话改期会看起来毫无效果。
                updated.pausedRemaining = max(0, targetDate.timeIntervalSince(now))
            }
        }
        items[index] = updated
        countdownCompletionPlayed.remove(updated.id)
        rescheduleCountdownNotifications()
    }

    func delete(_ item: CountdownItem) {
        items.removeAll { $0.id == item.id }
        countdownCompletionPlayed.remove(item.id)
        if !items.isEmpty, !items.contains(where: { $0.isPinned }) {
            items[0].isPinned = true
        }
        if selectedID == item.id {
            selectedID = items.first?.id
        }
        rescheduleCountdownNotifications()
    }

    func selectForDesktopWidget(_ item: CountdownItem) {
        items = items.map { candidate in
            var updated = candidate
            updated.isPinned = candidate.id == item.id
            return updated
        }
        selectedID = item.id
        // 已经是「两者」就别把模式退回单显示，用户是特意选的。
        if widgetDisplayMode == .both {
            reloadDesktopWidgetNow()
        } else {
            widgetDisplayMode = .countdown   // didSet 负责写盘和刷新
        }
    }

    func togglePause(_ item: CountdownItem) {
        var updated = item
        if let remaining = updated.pausedRemaining {
            updated.targetDate = Date().addingTimeInterval(remaining)
            updated.pausedRemaining = nil
        } else {
            updated.pausedRemaining = updated.remaining(at: Date())
        }
        countdownCompletionPlayed.remove(updated.id)
        update(updated)
        rescheduleCountdownNotifications()
        reloadDesktopWidgetNow()
    }

    func updatePomodoroTaskTitle(_ title: String) {
        var updated = pomodoro
        updated.taskTitle = title
        pomodoro = updated
    }

    /// 「本阶段尚未开始」——用状态本身判断，不依赖时钟，
    /// 这样按钮的可用性不需要每秒重算一遍界面。
    var canSwitchPomodoroTask: Bool {
        !pomodoro.isRunning && pomodoro.sessionStartedAt == nil && !pomodoro.isStopwatchActive
    }

    /// 给还没有颜色的任务补一个：旧数据迁移、以及任何漏分配的情况。
    private static func withAssignedColors(_ tasks: [PomodoroTask]) -> [PomodoroTask] {
        var result = tasks
        for index in result.indices where result[index].colorHex.isEmpty {
            result[index].colorHex = PomodoroTaskPalette.nextColorHex(after: result.map(\.colorHex))
        }
        return result
    }

    /// 统计里按任务取色：优先用任务上登记的颜色；历史里已删除的任务回落到标题推导。
    func taskColorHex(for title: String) -> String {
        let target = PomodoroTaskPalette.normalized(title)
        if let task = pomodoroTasks.first(where: { PomodoroTaskPalette.normalized($0.title) == target }),
           !task.colorHex.isEmpty {
            return task.colorHex
        }
        return PomodoroTaskPalette.fallbackColorHex(for: target)
    }

    func taskColor(for title: String) -> Color {
        Color(hex: taskColorHex(for: title))
    }

    func addPomodoroTask(title: String) {
        let trimmed = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        guard !trimmed.isEmpty else { return }
        if let existing = pomodoroTasks.first(where: {
            $0.title.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            selectPomodoroTask(existing.id)
            return
        }
        let task = PomodoroTask(
            title: trimmed,
            colorHex: PomodoroTaskPalette.nextColorHex(after: pomodoroTasks.map(\.colorHex))
        )
        pomodoroTasks.append(task)
        if canSwitchPomodoroTask {
            selectPomodoroTask(task.id)
        }
    }

    func selectPomodoroTask(_ id: UUID) {
        guard canSwitchPomodoroTask,
              let task = pomodoroTasks.first(where: { $0.id == id }) else { return }
        var updated = pomodoro
        updated.taskTitle = task.title
        pomodoro = updated
        reloadDesktopWidgetNow()
    }

    func deletePomodoroTask(_ task: PomodoroTask) {
        guard pomodoroTasks.count > 1 else { return }
        let isCurrent = task.title == pomodoro.taskTitle
        guard !isCurrent || canSwitchPomodoroTask else { return }
        pomodoroTasks.removeAll { $0.id == task.id }
        if isCurrent, let next = pomodoroTasks.first {
            selectPomodoroTask(next.id)
        }
    }

    func startOrPausePomodoro() {
        var updated = pomodoro
        let now = Date()
        if updated.isStopwatchActive {
            // 两个计时器互斥：开始番茄钟前先结算正计时，避免同一段时间被记两次。
            recordStopwatch(status: .stopwatch, at: now)
            updated = clearStopwatchState()
        }
        if updated.isRunning {
            updated.accumulatedElapsed = updated.elapsed(at: now)
            updated.pausedRemaining = updated.remaining(at: now)
            updated.endDate = nil
            updated.isRunning = false
            updated.activeStartedAt = nil
            cancelPomodoroNotifications()
        } else {
            let phaseDuration = updated.duration(for: updated.phase)
            let validRemaining = min(phaseDuration, max(0, updated.pausedRemaining))
            if validRemaining > 0 {
                updated.pausedRemaining = validRemaining
                updated.sessionStartedAt = updated.sessionStartedAt ?? now
            } else {
                // 剩余为 0 时按重新开始一整段处理，已用时长必须一起清零，
                // 否则 elapsed 会带着上一段的读数，让「停止并记录」记进旧时间。
                updated.pausedRemaining = phaseDuration
                updated.accumulatedElapsed = 0
                updated.sessionStartedAt = now
            }
            updated.activeStartedAt = now
            updated.endDate = now.addingTimeInterval(updated.pausedRemaining)
            updated.isRunning = true
            schedulePomodoroPhaseNotification(
                phase: updated.phase,
                endDate: updated.endDate!,
                taskTitle: updated.taskTitle
            )
        }
        pomodoro = updated
        reloadDesktopWidgetNow()
    }

    func startOrPauseStopwatch() {
        var updated = pomodoro
        let now = Date()
        if updated.isRunning {
            // 先结算进行中的番茄钟阶段，再开始正计时。
            recordCurrentPomodoro(status: .stopped, at: now)
            updated = clearCountdownState()
        }
        if updated.stopwatchRunning {
            updated.stopwatchAccumulated = updated.stopwatchElapsed(at: now)
            updated.stopwatchActiveStartedAt = nil
            updated.stopwatchRunning = false
        } else {
            updated.stopwatchSessionStartedAt = updated.stopwatchSessionStartedAt ?? now
            updated.stopwatchActiveStartedAt = now
            updated.stopwatchRunning = true
        }
        pomodoro = updated
        reloadDesktopWidgetNow()
    }

    func stopStopwatch() {
        let now = Date()
        if pomodoro.isRunning {
            // 从正计时侧停止时，如果番茄钟还在后台走，先一起结算，避免两边同时计时。
            recordCurrentPomodoro(status: .stopped, at: now)
            pomodoro = clearCountdownState()
        }
        recordStopwatch(status: .stopwatch, at: now)
        var updated = pomodoro
        updated.stopwatchRunning = false
        updated.stopwatchActiveStartedAt = nil
        updated.stopwatchSessionStartedAt = nil
        updated.stopwatchAccumulated = 0
        pomodoro = updated
        reloadDesktopWidgetNow()
    }

    func resetStopwatch() {
        let now = Date()
        if pomodoro.isRunning {
            recordCurrentPomodoro(status: .interrupted, at: now)
            pomodoro = clearCountdownState()
        }
        recordStopwatch(status: .interrupted, at: now)
        var updated = pomodoro
        updated.stopwatchRunning = false
        updated.stopwatchActiveStartedAt = nil
        updated.stopwatchSessionStartedAt = nil
        updated.stopwatchAccumulated = 0
        pomodoro = updated
        reloadDesktopWidgetNow()
    }

    func resetPomodoro() {
        let now = Date()
        if pomodoro.isStopwatchActive {
            recordStopwatch(status: .interrupted, at: now)
            pomodoro = clearStopwatchState()
        }
        recordCurrentPomodoro(status: .interrupted, at: now)
        var updated = pomodoro
        updated.isRunning = false
        updated.endDate = nil
        updated.pausedRemaining = updated.duration(for: updated.phase)
        updated.sessionStartedAt = nil
        updated.activeStartedAt = nil
        updated.accumulatedElapsed = 0
        cancelPomodoroNotifications()
        pomodoro = updated
        reloadDesktopWidgetNow()
    }

    func stopPomodoro() {
        let now = Date()
        if pomodoro.isStopwatchActive {
            recordStopwatch(status: .stopwatch, at: now)
            pomodoro = clearStopwatchState()
        }
        recordCurrentPomodoro(status: .stopped, at: now)
        var updated = pomodoro
        updated.isRunning = false
        updated.endDate = nil
        updated.pausedRemaining = updated.duration(for: updated.phase)
        updated.sessionStartedAt = nil
        updated.activeStartedAt = nil
        updated.accumulatedElapsed = 0
        cancelPomodoroNotifications()
        pomodoro = updated
        reloadDesktopWidgetNow()
    }

    func skipPomodoroPhase() {
        let now = Date()
        if pomodoro.isStopwatchActive {
            recordStopwatch(status: .stopwatch, at: now)
            pomodoro = clearStopwatchState()
        }
        advancePomodoro(countFocusCompletion: false, status: .skipped, at: now)
    }

    func updatePomodoroSettings(
        focusMinutes: Int,
        shortBreakMinutes: Int,
        longBreakMinutes: Int,
        roundsBeforeLongBreak: Int,
        weeklyFocusGoalMinutes: Int
    ) {
        let now = Date()
        var updated = pomodoro
        // 先按旧时长结算已用时间，改完时长后再据此重新推导剩余时间，
        // 这样「已经专注了 10 分钟」不会因为改设置而凭空消失或被重复计入。
        let elapsedBefore = updated.elapsed(at: now)
        updated.focusMinutes = min(120, max(1, focusMinutes))
        updated.shortBreakMinutes = min(30, max(1, shortBreakMinutes))
        updated.longBreakMinutes = min(60, max(1, longBreakMinutes))
        updated.roundsBeforeLongBreak = min(8, max(2, roundsBeforeLongBreak))
        updated.weeklyFocusGoalMinutes = min(168 * 60, max(60, weeklyFocusGoalMinutes))
        let newDuration = updated.duration(for: updated.phase)
        let carriedElapsed = min(elapsedBefore, newDuration)
        updated.accumulatedElapsed = carriedElapsed
        updated.pausedRemaining = max(0, newDuration - carriedElapsed)
        if updated.isRunning {
            updated.activeStartedAt = now
            updated.endDate = now.addingTimeInterval(updated.pausedRemaining)
        }
        pomodoro = updated
        reloadDesktopWidgetNow()
        if updated.isRunning, let endDate = updated.endDate {
            cancelPomodoroNotifications()
            schedulePomodoroPhaseNotification(
                phase: updated.phase,
                endDate: endDate,
                taskTitle: updated.taskTitle
            )
        } else {
            cancelPomodoroNotifications()
        }
    }

    func selectPomodoroForDesktopWidget() {
        savePomodoro()
        if widgetDisplayMode == .both {
            reloadDesktopWidgetNow()
        } else {
            widgetDisplayMode = .pomodoro
        }
    }

    func clearPomodoroHistory() {
        pomodoroHistory.removeAll()
    }

    // MARK: - 数据备份与恢复

    /// 存档解码失败时，把原始数据原样留存，避免用户数据被默认值静默覆盖。
    private static func preserveCorruptedDataIfNeeded(_ data: Data?, forKey key: String) {
        guard let data, !data.isEmpty else { return }
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("时隙/CorruptedBackups", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("\(key)-\(Int(Date().timeIntervalSince1970)).data")
            try data.write(to: url, options: .atomic)
        } catch {
            // 备份失败不影响启动
        }
    }

    /// 导出全部数据为可恢复的 JSON 备份。
    func exportBackup() -> Data? {
        let payload = BackupPayload(
            items: items,
            pomodoro: pomodoro,
            history: pomodoroHistory,
            tasks: pomodoroTasks,
            displayMode: widgetDisplayMode.rawValue,
            timeUnit: widgetTimeUnit,
            exportedAt: Date()
        )
        return try? JSONEncoder().encode(payload)
    }

    nonisolated static func decodeBackup(_ data: Data) throws -> BackupPayload {
        try JSONDecoder().decode(BackupPayload.self, from: data)
    }

    /// 用备份整体替换当前数据并刷新桌面小组件。
    func applyBackup(_ payload: BackupPayload) {
        items = payload.items
        pomodoro = payload.pomodoro
        pomodoroHistory = payload.history
        pomodoroTasks = CountdownStore.withAssignedColors(payload.tasks)
        widgetDisplayMode = WidgetDisplayMode(rawValue: payload.displayMode) ?? .both
        widgetTimeUnit = ["days", "hours", "precise", "auto"].contains(payload.timeUnit)
            ? payload.timeUnit : "days"
        selectedID = items.first?.id
        reloadDesktopWidgetNow()
        rescheduleAllNotifications()
    }

    private func handlePomodoroTick(at date: Date) {
        guard pomodoro.isRunning, pomodoro.remaining(at: date) <= 0 else { return }
        if soundsEnabled {
            NSSound(named: "Glass")?.play()
        }
        // App 在睡眠或锁屏后恢复时，tick 可能比真正结束时间晚很久。
        // 历史必须记在 endDate，否则会把一段 30 分钟专注摊到数小时甚至数天。
        advancePomodoro(
            countFocusCompletion: pomodoro.phase == .focus,
            status: .completed,
            at: pomodoro.completionDate(whenObservedAt: date)
        )
    }

    private func advancePomodoro(
        countFocusCompletion: Bool,
        status: PomodoroRecordStatus,
        at date: Date
    ) {
        recordCurrentPomodoro(status: status, at: date)
        var updated = pomodoro
        let leavingFocus = updated.phase == .focus
        if leavingFocus {
            if countFocusCompletion {
                updated.completedFocusSessions += 1
            }
            let reachesLongBreak = countFocusCompletion
                && updated.completedFocusSessions > 0
                && updated.completedFocusSessions % updated.roundsBeforeLongBreak == 0
            updated.phase = reachesLongBreak ? .longBreak : .shortBreak
        } else {
            updated.phase = .focus
        }
        updated.endDate = nil
        updated.pausedRemaining = updated.duration(for: updated.phase)
        updated.accumulatedElapsed = 0
        if leavingFocus {
            // 专注结束后休息自动开始计时；休息结束回到专注则仍然等用户主动按开始。
            updated.isRunning = true
            updated.sessionStartedAt = date
            updated.activeStartedAt = date
            updated.endDate = date.addingTimeInterval(updated.pausedRemaining)
            schedulePomodoroPhaseNotification(
                phase: updated.phase,
                endDate: updated.endDate!,
                taskTitle: updated.taskTitle
            )
        } else {
            updated.isRunning = false
            updated.sessionStartedAt = nil
            updated.activeStartedAt = nil
            cancelPomodoroNotifications()
        }
        pomodoro = updated
        reloadDesktopWidgetNow()
    }

    private func recordCurrentPomodoro(status: PomodoroRecordStatus, at date: Date) {
        let actualDuration = pomodoro.elapsed(at: date)
        guard actualDuration >= Self.minimumMeaningfulSessionDuration else { return }
        let startedAt = pomodoro.sessionStartedAt ?? date.addingTimeInterval(-actualDuration)
        let record = PomodoroSessionRecord(
            phase: pomodoro.phase,
            taskTitle: pomodoro.taskTitle,
            plannedDuration: pomodoro.duration(for: pomodoro.phase),
            actualDuration: actualDuration,
            startedAt: startedAt,
            endedAt: date,
            status: status
        )
        pomodoroHistory.insert(record, at: 0)
        if pomodoroHistory.count > 200 {
            pomodoroHistory.removeLast(pomodoroHistory.count - 200)
        }
    }

    private func recordStopwatch(status: PomodoroRecordStatus, at date: Date) {
        let actualDuration = pomodoro.stopwatchElapsed(at: date)
        guard actualDuration >= Self.minimumMeaningfulSessionDuration else { return }
        let startedAt = pomodoro.stopwatchSessionStartedAt
            ?? date.addingTimeInterval(-actualDuration)
        let record = PomodoroSessionRecord(
            phase: .focus,
            taskTitle: pomodoro.taskTitle,
            plannedDuration: actualDuration,
            actualDuration: actualDuration,
            startedAt: startedAt,
            endedAt: date,
            status: status
        )
        pomodoroHistory.insert(record, at: 0)
        if pomodoroHistory.count > 200 {
            pomodoroHistory.removeLast(pomodoroHistory.count - 200)
        }
    }

    /// 结算完正计时后，把正计时状态彻底清空，避免残留字段影响任务锁定和小组件显示。
    private func clearStopwatchState() -> PomodoroState {
        var updated = pomodoro
        updated.stopwatchRunning = false
        updated.stopwatchActiveStartedAt = nil
        updated.stopwatchSessionStartedAt = nil
        updated.stopwatchAccumulated = 0
        return updated
    }

    /// 结算完番茄钟阶段后，把倒计时状态彻底清空，避免残留字段让两个计时器同时运行。
    private func clearCountdownState() -> PomodoroState {
        var updated = pomodoro
        updated.isRunning = false
        updated.endDate = nil
        updated.sessionStartedAt = nil
        updated.activeStartedAt = nil
        updated.pausedRemaining = updated.duration(for: updated.phase)
        updated.accumulatedElapsed = 0
        return updated
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        CountdownStore.saveSharedData(data, forKey: storageKey)
        persistWidgetStateFile()
        scheduleWidgetReload()
    }

    private func savePomodoro() {
        guard let data = try? JSONEncoder().encode(pomodoro) else { return }
        CountdownStore.saveSharedData(data, forKey: pomodoroStorageKey)
        persistWidgetStateFile()
        scheduleWidgetReload()
    }

    private func savePomodoroHistory() {
        guard let data = try? JSONEncoder().encode(pomodoroHistory) else { return }
        CountdownStore.saveSharedData(data, forKey: pomodoroHistoryStorageKey)
        persistWidgetStateFile()
        scheduleWidgetReload()
    }

    private func savePomodoroTasks() {
        guard let data = try? JSONEncoder().encode(pomodoroTasks) else { return }
        CountdownStore.saveSharedData(data, forKey: pomodoroTasksStorageKey)
    }

    private func persistSharedStateWithoutWidgetReload() {
        if let data = try? JSONEncoder().encode(items) {
            CountdownStore.saveSharedData(data, forKey: storageKey)
        }
        if let data = try? JSONEncoder().encode(pomodoro) {
            CountdownStore.saveSharedData(data, forKey: pomodoroStorageKey)
        }
        persistWidgetStateFile()
    }

    private func scheduleWidgetReload() {
        widgetReloadTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.widgetReloadTask = nil
            self.performWidgetReload()
        }
        widgetReloadTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: task)
    }

    private func reloadDesktopWidgetNow() {
        widgetReloadTask?.cancel()
        widgetReloadTask = nil
        performWidgetReload()
        // 写共享文件与扩展进程读取之间没有同步保证，补一次兜底即可。
        // 之前在此叠加 0.4s/1.5s 两次 Task，一次状态变化最多触发 4 次 × 6 kinds
        // 的 reloadTimelines，极易被 WidgetKit 预算节流合并，反而表现为“小组件不更新”。
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            self?.performWidgetReload()
        }
    }

    private func performWidgetReload() {
        for kind in Self.widgetKinds {
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
        }
    }

    // MARK: - 通知调度（番茄钟阶段 + 倒计时完成）

    private static func countdownNotificationIdentifier(for item: CountdownItem) -> String {
        "countdown.completion.\(item.id.uuidString)"
    }

    /// 番茄钟阶段结束通知。identifier 由阶段与结束时间戳构成，同一阶段重复调度会覆盖旧请求。
    private func schedulePomodoroPhaseNotification(phase: PomodoroPhase, endDate: Date, taskTitle: String) {
        guard notificationsEnabled, notificationPermissionGranted else { return }
        let identifier = "pomodoro.phase.end.\(phase.rawValue).\(Int(endDate.timeIntervalSince1970))"
        let content = UNMutableNotificationContent()
        content.title = "时隙"
        switch phase {
        case .focus:
            content.body = "「\(taskTitle.isEmpty ? "专注" : taskTitle)」完成，休息一下"
        case .shortBreak:
            content.body = "休息结束，开始下一轮专注"
        case .longBreak:
            content.body = "长休息结束，开始新的专注轮次"
        }
        content.sound = .default
        var components = beijingCalendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: endDate)
        components.calendar = beijingCalendar
        components.timeZone = beijingTimeZone
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
        pendingPomodoroNotificationIDs.insert(identifier)
        UNUserNotificationCenter.current().add(request)
    }

    private func cancelPomodoroNotifications() {
        guard !pendingPomodoroNotificationIDs.isEmpty else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: Array(pendingPomodoroNotificationIDs)
        )
        pendingPomodoroNotificationIDs.removeAll()
    }

    /// 取消应用排入队列的全部通知（番茄钟 + 倒计时）。
    private func cancelAllScheduledNotifications() {
        var ids = Set(pendingPomodoroNotificationIDs)
        ids.formUnion(items.map { Self.countdownNotificationIdentifier(for: $0) })
        guard !ids.isEmpty else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: Array(ids))
        pendingPomodoroNotificationIDs.removeAll()
    }

    /// 根据当前状态重建全部通知（倒计时 + 运行中的番茄钟阶段）。
    private func rescheduleAllNotifications() {
        cancelAllScheduledNotifications()
        guard notificationsEnabled, notificationPermissionGranted else { return }
        for item in items where CountdownNotificationPolicy.shouldSchedule(item: item, at: Date()) {
            scheduleCountdownNotification(for: item)
        }
        if pomodoro.isRunning, let endDate = pomodoro.endDate {
            schedulePomodoroPhaseNotification(
                phase: pomodoro.phase,
                endDate: endDate,
                taskTitle: pomodoro.taskTitle
            )
        }
    }

    private func requestNotificationPermissionIfNeeded() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            switch settings.authorizationStatus {
            case .notDetermined:
                let hasActiveTimer = self.items.contains { item in
                    CountdownNotificationPolicy.shouldSchedule(item: item, at: Date())
                } || self.pomodoro.isRunning
                guard hasActiveTimer else { return }
                let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
                self.notificationPermissionGranted = granted
                if granted {
                    self.rescheduleAllNotifications()
                }
            case .authorized, .provisional, .ephemeral:
                self.notificationPermissionGranted = true
                self.rescheduleAllNotifications()
            default:
                self.notificationPermissionGranted = false
            }
        }
    }

    private func rescheduleCountdownNotifications() {
        rescheduleAllNotifications()
    }

    private func scheduleCountdownNotification(for item: CountdownItem) {
        let content = UNMutableNotificationContent()
        content.title = "倒计时结束"
        content.body = "「\(item.title)」时间到"
        content.sound = .default
        var components = beijingCalendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: item.targetDate
        )
        components.calendar = beijingCalendar
        components.timeZone = beijingTimeZone
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: Self.countdownNotificationIdentifier(for: item),
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// 倒计时归零时给一次反馈：通知权限已授予时由系统通知响铃，
    /// 未授予时用应用内提示音兜底（只对刚结束的目标响，不骚扰历史数据）。
    private func checkCountdownCompletions(at date: Date) {
        for item in items where item.pausedRemaining == nil && !countdownCompletionPlayed.contains(item.id) {
            guard item.remaining(at: date) <= 0 else { continue }
            countdownCompletionPlayed.insert(item.id)
            reloadDesktopWidgetNow()
            guard abs(date.timeIntervalSince(item.targetDate)) <= 30 else { continue }
            if !notificationPermissionGranted && soundsEnabled {
                NSSound(named: "Glass")?.play()
            }
        }
    }
}
