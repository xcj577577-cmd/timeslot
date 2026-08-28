import AppKit
import Combine
import SwiftUI
import WidgetKit
import UserNotifications

@MainActor
final class CountdownStore: ObservableObject {
    @Published var items: [CountdownItem] {
        didSet {
            save()
            configureTimerIfNeeded()
        }
    }
    @Published var selectedID: UUID? {
        didSet {
            countdownDefaults.set(selectedID?.uuidString, forKey: "selectedCountdownID")
        }
    }
    @Published var pomodoro: PomodoroState {
        didSet {
            savePomodoro()
            configureTimerIfNeeded()
        }
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
            persistWidgetStateFile(requestReload: false)
            reloadDesktopWidgetNow()
        }
    }
    @Published var widgetTimeUnit: String {
        didSet {
            CountdownStore.saveSharedString(widgetTimeUnit, forKey: widgetTimeUnitKey)
            persistWidgetStateFile(requestReload: false)
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
    @Published private(set) var widgetSyncState: WidgetSyncState = .checking
    @Published private(set) var notificationPermissionState: NotificationPermissionState = .checking
    @Published private(set) var undoableAction: UndoableStoreAction? = nil
    @Published private(set) var storageMigrationState: StorageMigrationState = .current

    private var timerCancellable: AnyCancellable?
    private var timerInterval: TimeInterval?
    private var widgetDelayedReloadTask: Task<Void, Never>?
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
    private struct CountdownDeletionSnapshot {
        let item: CountdownItem
        let index: Int
        let selectedID: UUID?
        let promotedPinID: UUID?
        let promotedPinValue: Bool
    }
    private var countdownDeletionSnapshot: CountdownDeletionSnapshot?
    private var pomodoroHistoryDeletionSnapshot: [PomodoroSessionRecord]?
    private var undoExpirationTask: Task<Void, Never>?
    private var undoGeneration = 0
    /// 已排入系统队列的番茄钟阶段通知 id，暂停/重置/停顿时按 id 精确取消，不误删倒计时通知。
    private var pendingPomodoroNotificationIDs: Set<String> = []
    /// 通知队列查询是异步的。用代次丢弃较早的重建任务，避免快速编辑/删除时
    /// 旧任务在最后反而把刚排好的新通知清掉。
    private var notificationRescheduleGeneration = 0
    private static let sharedDefaultsName = "4FKFDX48HX.com.xianz.countdownwidget.shared"
    private let storageKey = "countdownItems"
    private let pomodoroStorageKey = "pomodoroState"
    private let pomodoroHistoryStorageKey = "pomodoroHistory"
    private let pomodoroTasksStorageKey = "pomodoroTasks"
    private let widgetDisplayModeKey = "widgetDisplayMode"
    private let widgetTimeUnitKey = "widgetTimeUnit"
    private let accentPresetKey = "accentPreset"
    private let appearanceModeKey = "appearanceMode"
    private static let storageSchemaVersionKey = "storageSchemaVersion"
    /// 不足 10 秒的专注/阶段没有统计意义，不写入历史，启动时也会清掉旧数据。
    private static let minimumMeaningfulSessionDuration: TimeInterval = 10
    private static let maximumHistoryCount = 10_000
    private static let pomodoroNotificationIdentifier = TimeSlotNotificationIdentifier.pomodoroPhaseEnd
    private static let validWidgetTimeUnits = ["days", "hours", "precise", "auto"]
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

    private static let migrationDataKeys = [
        "countdownItems",
        "pomodoroState",
        "pomodoroHistory",
        "pomodoroTasks"
    ]

    private static let migrationStringKeys = [
        "widgetDisplayMode",
        "widgetTimeUnit",
        "accentPreset",
        "appearanceMode",
        "selectedCountdownID",
        "enableNotifications",
        "enableSounds",
        "pomodoroHistoryRange",
        "pomodoroTimerMode"
    ]

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

    private func persistWidgetStateFile(requestReload: Bool = true) {
        guard let url = widgetStateURL else {
            widgetSyncState = .unavailable
            return
        }
        let state = WidgetStateFile(
            items: items,
            pomodoro: pomodoro,
            pomodoroHistory: widgetHistorySnapshot(),
            displayMode: widgetDisplayMode.rawValue,
            timeUnit: widgetTimeUnit,
            updatedAt: Date()
        )
        guard let data = try? JSONEncoder().encode(state) else { return }
        let directory = url.deletingLastPathComponent()
        let widgetKinds = requestReload ? Self.widgetKinds : []
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
                let message = error.localizedDescription
                Task { @MainActor [weak self] in
                    self?.widgetSyncState = .failed(message)
                }
            }
            guard didWrite else { return }
            Task { @MainActor [weak self] in
                self?.widgetSyncState = .ready(state.updatedAt)
            }
            // 只有原子文件写完后才请求 WidgetKit 重建，避免扩展先读到旧快照。
            for kind in widgetKinds {
                WidgetCenter.shared.reloadTimelines(ofKind: kind)
            }
        }
    }

    private func widgetHistorySnapshot() -> [PomodoroSessionRecord] {
        let cutoff = beijingCalendar.date(byAdding: .day, value: -8, to: Date())
            ?? Date().addingTimeInterval(-8 * 86_400)
        return pomodoroHistory.filter { $0.endedAt >= cutoff }
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

    private static func storedStorageSchemaVersion() -> Int? {
        guard let value = countdownDefaults.object(forKey: storageSchemaVersionKey) else {
            return nil
        }
        return value as? Int
    }

    private static func markStorageSchemaCurrent() {
        countdownDefaults.set(LocalStorageMigration.currentSchemaVersion, forKey: storageSchemaVersionKey)
        countdownDefaults.set(Date(), forKey: "storageSchemaMigratedAt")
    }

    /// 保存旧版原始键值，作为迁移的可回退证据。只在版本升级时执行一次。
    /// 文件使用 Property List 表示，不改变用户现有的共享键，也不需要网络或数据库。
    private static func preserveLegacyStorageSnapshotIfNeeded() -> Bool {
        var values: [String: Data] = [:]
        for key in migrationDataKeys {
            if let data = countdownDefaults.data(forKey: key), !data.isEmpty {
                values[key] = data
            }
        }

        var preferences: [String: Data] = [:]
        for key in migrationStringKeys {
            if let rawValue = countdownDefaults.object(forKey: key) {
                if let data = try? PropertyListSerialization.data(
                    fromPropertyList: rawValue,
                    format: .binary,
                    options: 0
                ) {
                    preferences[key] = data
                }
            }
        }
        guard !values.isEmpty || !preferences.isEmpty else { return true }

        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return false }

        let formatter = ISO8601DateFormatter()
        let stamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let directory = applicationSupport
            .appendingPathComponent("时隙/Migrations", isDirectory: true)
            .appendingPathComponent(
                "storage-v1-" + stamp + "-" + String(UUID().uuidString.prefix(8)),
                isDirectory: true
            )

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try PropertyListSerialization.data(
                fromPropertyList: values,
                format: .binary,
                options: 0
            ).write(to: directory.appendingPathComponent("data.plist"), options: .atomic)
            try PropertyListSerialization.data(
                fromPropertyList: preferences,
                format: .binary,
                options: 0
            ).write(to: directory.appendingPathComponent("preferences.plist"), options: .atomic)
            return true
        } catch {
            return false
        }
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

    func refreshNotificationPermissionStatus() {
        updateNotificationPermission(requestIfNeeded: false)
    }

    func requestNotificationPermission() {
        updateNotificationPermission(requestIfNeeded: true, forceRequest: true)
    }

    func openNotificationSettings() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.xianz.countdownwidget"
        let urlString = "x-apple.systempreferences:com.apple.Notifications-Settings?bundleID=\(bundleID)"
        guard let url = URL(string: urlString) else { return }
        NSApp.activate(ignoringOtherApps: true)
        NSWorkspace.shared.open(url)
    }

    func setSoundsEnabled(_ enabled: Bool) {
        soundsEnabled = enabled
        rescheduleAllNotifications()
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
        let storedStorageSchemaVersion = Self.storedStorageSchemaVersion()
        let needsStorageMigration = LocalStorageMigration.needsMigration(
            storedVersion: storedStorageSchemaVersion
        )
        let migrationSnapshotReady = !needsStorageMigration
            || Self.preserveLegacyStorageSnapshotIfNeeded()
        let sharedWidgetState = Self.loadWidgetStateFile()
        let shouldRestoreRunningPomodoro = sharedWidgetState?.pomodoro.isRunning == true
            || sharedWidgetState?.pomodoro.isStopwatchActive == true
        // cfprefsd 可能保留旧缓存；启动前先同步一次，避免把仍在运行的番茄钟读成旧状态。
        if !shouldRestoreRunningPomodoro {
            countdownDefaults.synchronize()
        }
        let storedItemsData = CountdownStore.loadSharedData(forKey: storageKey)
        var loadedItems: [CountdownItem]
        switch CountdownItemsStoragePolicy.resolve(storedItemsData) {
        case .decoded(let saved):
            // 空数组代表用户明确删除了全部倒计时，不能在下次启动时悄悄塞回示例数据。
            loadedItems = saved
        case .corrupted:
            Self.preserveCorruptedDataIfNeeded(storedItemsData, forKey: storageKey)
            loadedItems = Self.defaultCountdownItems()
        case .missing:
            loadedItems = Self.defaultCountdownItems()
        }
        // 桌面小组件取的是第一个 isPinned 的条目，所以这里保证有且只有一个被选中。
        // 已有数据两种都可能坏：旧版默认值 true 会让多条同时选中（界面上每条都显示
        // 「当前内容」），更旧的数据又完全没有这个字段、回落成一条都没选。
        loadedItems = Self.normalizedCountdownItems(loadedItems)
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
        let loadedPomodoro: PomodoroState
        if shouldRestoreRunningPomodoro, let sharedWidgetState {
            loadedPomodoro = sharedWidgetState.pomodoro
        } else {
            loadedPomodoro = loadedPomodoroFromDefaults
        }
        pomodoro = loadedPomodoro
        if let data = CountdownStore.loadSharedData(forKey: pomodoroHistoryStorageKey) {
            do {
                let saved = try JSONDecoder().decode([PomodoroSessionRecord].self, from: data)
                pomodoroHistory = saved
                    .filter {
                        $0.actualDuration.isFinite
                            && $0.actualDuration >= Self.minimumMeaningfulSessionDuration
                    }
                    .sorted { $0.endedAt > $1.endedAt }
                    .prefix(Self.maximumHistoryCount)
                    .map { $0 }
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
        pomodoroTasks = CountdownStore.normalizedTasks(
            loadedTasks,
            currentTaskTitle: currentTaskTitle
        )
        widgetDisplayMode = CountdownStore.loadSharedString(forKey: widgetDisplayModeKey)
            .flatMap(WidgetDisplayMode.init(rawValue:)) ?? .both
        let storedTimeUnit = CountdownStore.loadSharedString(forKey: widgetTimeUnitKey) ?? "auto"
        widgetTimeUnit = Self.validWidgetTimeUnits.contains(storedTimeUnit) ? storedTimeUnit : "auto"
        let storedID = countdownDefaults.string(forKey: "selectedCountdownID").flatMap(UUID.init(uuidString:))
        accentPreset = ColorPreset(rawValue: countdownDefaults.string(forKey: accentPresetKey) ?? "") ?? .graphite
        appearanceMode = AppAppearance(rawValue: countdownDefaults.string(forKey: appearanceModeKey) ?? "") ?? .system
        NSApp.appearance = appearanceMode.nsAppearance
        selectedID = storedID.flatMap { id in items.contains(where: { $0.id == id }) ? id : nil } ?? items.first?.id

        configureTimerIfNeeded()

        persistSharedStateWithoutWidgetReload()
        savePomodoroHistory()
        savePomodoroTasks()
        if needsStorageMigration, migrationSnapshotReady {
            Self.markStorageSchemaCurrent()
            storageMigrationState = .migrated(from: storedStorageSchemaVersion)
        } else if needsStorageMigration {
            storageMigrationState = .pending("未能创建迁移快照；现有数据未标记为已升级，请稍后重试")
        } else {
            storageMigrationState = .current
        }
        updateNotificationPermission(requestIfNeeded: true)
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
        requestNotificationPermissionIfNeeded()
        rescheduleCountdownNotifications()
    }

    func update(_ item: CountdownItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = item
    }

    func applyEdit(to item: CountdownItem, title: String, targetDate: Date, colorHex: String) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        var updated = items[index]
        updated.title = CountdownItem.normalizedTitle(title)
        updated.colorHex = ColorHex.normalized(colorHex)
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
        requestNotificationPermissionIfNeeded()
        rescheduleCountdownNotifications()
    }

    func delete(_ item: CountdownItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let selectedBeforeDeletion = selectedID
        items.remove(at: index)
        countdownCompletionPlayed.remove(item.id)
        var promotedPinID: UUID?
        var promotedPinValue = false
        if !items.isEmpty, !items.contains(where: { $0.isPinned }) {
            promotedPinID = items[0].id
            promotedPinValue = items[0].isPinned
            items[0].isPinned = true
        }
        if selectedID == item.id {
            selectedID = items.first?.id
        }
        rescheduleCountdownNotifications()
        offerUndo(
            .countdownDeleted(title: item.title),
            countdownSnapshot: CountdownDeletionSnapshot(
                item: item,
                index: index,
                selectedID: selectedBeforeDeletion,
                promotedPinID: promotedPinID,
                promotedPinValue: promotedPinValue
            )
        )
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
        updated.taskTitle = String(PomodoroTaskPalette.normalized(title).prefix(40))
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
        for index in result.indices {
            if result[index].colorHex.isEmpty {
                result[index].colorHex = PomodoroTaskPalette.nextColorHex(after: result.map(\.colorHex))
            } else {
                result[index].colorHex = ColorHex.normalized(result[index].colorHex)
            }
        }
        return result
    }

    private static func normalizedCountdownItems(_ candidates: [CountdownItem]) -> [CountdownItem] {
        var seenIDs = Set<UUID>()
        var result: [CountdownItem] = []
        result.reserveCapacity(candidates.count)
        for var item in candidates where seenIDs.insert(item.id).inserted {
            item.title = CountdownItem.normalizedTitle(item.title)
            item.colorHex = ColorHex.normalized(item.colorHex)
            item.totalDuration = item.totalDuration.isFinite ? max(1, item.totalDuration) : 1
            if let paused = item.pausedRemaining {
                item.pausedRemaining = paused.isFinite ? max(0, paused) : nil
            }
            result.append(item)
        }

        if let pinnedIndex = result.firstIndex(where: { $0.isPinned }) {
            for index in result.indices where index != pinnedIndex {
                result[index].isPinned = false
            }
        } else if !result.isEmpty {
            result[0].isPinned = true
        }
        return result
    }

    private static func normalizedTasks(
        _ candidates: [PomodoroTask],
        currentTaskTitle: String
    ) -> [PomodoroTask] {
        var seenIDs = Set<UUID>()
        var seenTitles = Set<String>()
        var result: [PomodoroTask] = []

        for var task in candidates where seenIDs.insert(task.id).inserted {
            task.title = String(PomodoroTaskPalette.normalized(task.title).prefix(40))
            let comparisonKey = task.title.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: beijingLocale
            )
            guard seenTitles.insert(comparisonKey).inserted else { continue }
            result.append(task)
        }

        let normalizedCurrent = String(PomodoroTaskPalette.normalized(currentTaskTitle).prefix(40))
        let currentKey = normalizedCurrent.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: beijingLocale
        )
        if !seenTitles.contains(currentKey) {
            result.insert(PomodoroTask(title: normalizedCurrent), at: 0)
        }
        if result.isEmpty {
            result = [PomodoroTask(title: normalizedCurrent)]
        }
        return withAssignedColors(result)
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
        if updated.isRunning {
            requestNotificationPermissionIfNeeded()
        }
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
        guard !pomodoroHistory.isEmpty else { return }
        let snapshot = pomodoroHistory
        pomodoroHistory.removeAll()
        offerUndo(
            .pomodoroHistoryCleared(count: snapshot.count),
            historySnapshot: snapshot
        )
    }

    func deletePomodoroHistory(ids: [UUID], title: String? = nil) {
        let idSet = Set(ids)
        guard !idSet.isEmpty else { return }
        let snapshot = pomodoroHistory.filter { idSet.contains($0.id) }
        guard !snapshot.isEmpty else { return }
        pomodoroHistory.removeAll { idSet.contains($0.id) }
        let label = title ?? snapshot.first.map { PomodoroTaskPalette.normalized($0.taskTitle) } ?? "阶段"
        offerUndo(
            .pomodoroRecordsDeleted(count: snapshot.count, title: label),
            historySnapshot: snapshot
        )
    }

    /// 修正一条历史记录的起止时间与任务名，实际时长按新的墙钟重新计算。
    /// 用于补救「忘了停止计时」导致的异常长/短记录。
    func updatePomodoroHistoryRecord(id: UUID, startedAt: Date, endedAt: Date, taskTitle: String) {
        guard let index = pomodoroHistory.firstIndex(where: { $0.id == id }) else { return }
        let end = max(startedAt, endedAt)
        let wall = end.timeIntervalSince(startedAt)
        guard wall > 0 else { return }
        let previous = pomodoroHistory[index]
        let previousWall = previous.endedAt.timeIntervalSince(previous.startedAt)
        let newActual: TimeInterval
        if previousWall > 0, previous.actualDuration <= previousWall {
            // 原记录含暂停（实际用时小于墙钟），按比例缩放保持语义
            newActual = previous.actualDuration * (wall / previousWall)
        } else {
            newActual = wall
        }
        pomodoroHistory[index] = PomodoroSessionRecord(
            id: previous.id,
            phase: previous.phase,
            taskTitle: PomodoroTaskPalette.normalized(taskTitle),
            plannedDuration: previous.plannedDuration,
            actualDuration: newActual,
            startedAt: startedAt,
            endedAt: end,
            status: previous.status
        )
    }

    func undoLastAction() {
        guard let action = undoableAction else { return }
        switch action {
        case .countdownDeleted:
            guard let snapshot = countdownDeletionSnapshot,
                  !items.contains(where: { $0.id == snapshot.item.id }) else {
                clearUndoState()
                return
            }
            let insertionIndex = min(max(snapshot.index, 0), items.count)
            items.insert(snapshot.item, at: insertionIndex)
            if let promotedPinID = snapshot.promotedPinID,
               let promotedIndex = items.firstIndex(where: { $0.id == promotedPinID }) {
                items[promotedIndex].isPinned = snapshot.promotedPinValue
            }
            if let selectedID = snapshot.selectedID {
                self.selectedID = items.contains(where: { $0.id == selectedID })
                    ? selectedID
                    : items.first?.id
            } else {
                self.selectedID = nil
            }
            countdownCompletionPlayed.remove(snapshot.item.id)
            rescheduleCountdownNotifications()

        case .pomodoroHistoryCleared, .pomodoroRecordsDeleted:
            guard let snapshot = pomodoroHistoryDeletionSnapshot else {
                clearUndoState()
                return
            }
            var restored = pomodoroHistory
            let existingIDs = Set(restored.map(\.id))
            restored.append(contentsOf: snapshot.filter { !existingIDs.contains($0.id) })
            pomodoroHistory = restored.sorted { lhs, rhs in
                lhs.endedAt > rhs.endedAt
            }
        }
        clearUndoState()
    }

    private func offerUndo(
        _ action: UndoableStoreAction,
        countdownSnapshot: CountdownDeletionSnapshot? = nil,
        historySnapshot: [PomodoroSessionRecord]? = nil
    ) {
        clearUndoState()
        undoableAction = action
        countdownDeletionSnapshot = countdownSnapshot
        pomodoroHistoryDeletionSnapshot = historySnapshot
        let generation = undoGeneration
        undoExpirationTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 8_000_000_000)
            } catch {
                return
            }
            guard let self, self.undoGeneration == generation else { return }
            self.clearUndoState()
        }
    }

    private func clearUndoState() {
        undoExpirationTask?.cancel()
        undoExpirationTask = nil
        countdownDeletionSnapshot = nil
        pomodoroHistoryDeletionSnapshot = nil
        undoableAction = nil
        undoGeneration &+= 1
    }

    func refreshDesktopWidgets() {
        persistWidgetStateFile(requestReload: false)
        reloadDesktopWidgetNow()
    }

    // MARK: - 数据备份与恢复

    /// 存档解码失败时，把原始数据原样留存，避免用户数据被默认值静默覆盖。
    private static func preserveCorruptedDataIfNeeded(_ data: Data?, forKey key: String) {
        guard let data, !data.isEmpty else { return }
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return }
        let directory = applicationSupport.appendingPathComponent("时隙/CorruptedBackups", isDirectory: true)
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
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try? encoder.encode(payload)
    }

    nonisolated static func decodeBackup(_ data: Data) throws -> BackupPayload {
        guard data.count <= BackupValidationPolicy.maximumFileSize else {
            throw BackupValidationError.fileTooLarge
        }
        let payload = try JSONDecoder().decode(BackupPayload.self, from: data)
        try BackupValidationPolicy.validate(dataSize: data.count, payload: payload)
        return payload
    }

    /// 用备份整体替换当前数据并刷新桌面小组件。
    func applyBackup(_ payload: BackupPayload) throws {
        try preserveAutomaticBackupBeforeImport()
        items = Self.normalizedCountdownItems(payload.items)
        var restoredPomodoro = payload.pomodoro
        restoredPomodoro.normalizeForRuntime()
        pomodoro = restoredPomodoro
        pomodoroHistory = payload.history
            .filter { $0.actualDuration.isFinite && $0.actualDuration >= Self.minimumMeaningfulSessionDuration }
            .sorted { $0.endedAt > $1.endedAt }
            .prefix(Self.maximumHistoryCount)
            .map { $0 }
        pomodoroTasks = CountdownStore.normalizedTasks(
            payload.tasks,
            currentTaskTitle: restoredPomodoro.taskTitle
        )
        widgetDisplayMode = WidgetDisplayMode(rawValue: payload.displayMode) ?? .both
        widgetTimeUnit = Self.validWidgetTimeUnits.contains(payload.timeUnit)
            ? payload.timeUnit : "auto"
        selectedID = items.first(where: \.isPinned)?.id ?? items.first?.id
        reloadDesktopWidgetNow()
        rescheduleAllNotifications()
    }

    private func preserveAutomaticBackupBeforeImport() throws {
        guard let data = exportBackup() else {
            throw BackupOperationError.cannotEncodeCurrentData
        }
        guard let applicationSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
              ).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        let directory = applicationSupport.appendingPathComponent("时隙/AutomaticBackups", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let formatter = ISO8601DateFormatter()
        let stamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let suffix = UUID().uuidString.prefix(8)
        try data.write(
            to: directory.appendingPathComponent("导入前自动备份-\(stamp)-\(suffix).json"),
            options: .atomic
        )
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
        if pomodoroHistory.count > Self.maximumHistoryCount {
            pomodoroHistory.removeLast(pomodoroHistory.count - Self.maximumHistoryCount)
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
        if pomodoroHistory.count > Self.maximumHistoryCount {
            pomodoroHistory.removeLast(pomodoroHistory.count - Self.maximumHistoryCount)
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
    }

    /// Store 只在需要观察状态跃迁时运行定时器：番茄钟运行中或倒计时临近到期按秒检查，
    /// 远期目标每分钟检查，完全空闲时停止定时器。秒级读数由各自的 TimelineView 负责。
    private func configureTimerIfNeeded(at date: Date = Date()) {
        let nearestCountdown = items
            .filter { !$0.isPaused }
            .map { $0.remaining(at: date) }
            .filter { $0 > 0 }
            .min()
        let desiredInterval: TimeInterval?
        if pomodoro.isRunning {
            desiredInterval = 1
        } else if let nearestCountdown {
            desiredInterval = nearestCountdown <= 120 ? 1 : 60
        } else {
            desiredInterval = nil
        }

        guard desiredInterval != timerInterval else { return }
        timerCancellable?.cancel()
        timerCancellable = nil
        timerInterval = desiredInterval
        guard let desiredInterval else { return }

        timerCancellable = Timer.publish(every: desiredInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] date in
                guard let self else { return }
                // 这个 tick 只用来判定阶段是否结束，不再每秒发布状态。
                // 秒级读数由各自的 TimelineView 负责。
                self.handlePomodoroTick(at: date)
                self.checkCountdownCompletions(at: date)
                self.configureTimerIfNeeded(at: date)
                // 兜底同步：即使扩展进程的刷新请求被系统合并或错过，
                // 应用只要开着，每 4 分钟也会主动让小组件重新读取一次状态。
                if date.timeIntervalSince(self.lastWidgetHealthReload) >= 240 {
                    self.lastWidgetHealthReload = date
                    self.performWidgetReload()
                }
            }
    }

    private func savePomodoro() {
        guard let data = try? JSONEncoder().encode(pomodoro) else { return }
        CountdownStore.saveSharedData(data, forKey: pomodoroStorageKey)
        persistWidgetStateFile()
    }

    private func savePomodoroHistory() {
        guard let data = try? JSONEncoder().encode(pomodoroHistory) else { return }
        CountdownStore.saveSharedData(data, forKey: pomodoroHistoryStorageKey)
        persistWidgetStateFile()
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
        persistWidgetStateFile(requestReload: false)
    }

    private func reloadDesktopWidgetNow() {
        widgetDelayedReloadTask?.cancel()
        widgetDelayedReloadTask = nil
        performWidgetReload()
        // 写共享文件与扩展进程读取之间没有同步保证，补一次兜底即可。
        // 之前在此叠加 0.4s/1.5s 两次 Task，一次状态变化最多触发 4 次 × 6 kinds
        // 的 reloadTimelines，极易被 WidgetKit 预算节流合并，反而表现为“小组件不更新”。
        widgetDelayedReloadTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 800_000_000)
            } catch {
                return
            }
            guard let self else { return }
            self.widgetDelayedReloadTask = nil
            self.performWidgetReload()
        }
    }

    private func performWidgetReload() {
        for kind in Self.widgetKinds {
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
        }
    }

    // MARK: - 通知调度（番茄钟阶段 + 倒计时完成）

    private static func countdownNotificationIdentifier(for item: CountdownItem) -> String {
        TimeSlotNotificationIdentifier.countdownCompletion(for: item.id)
    }

    /// 番茄钟始终只保留一条阶段通知。固定 identifier 能跨进程覆盖旧请求，
    /// 避免应用重启后，旧阶段通知在错误时间再次弹出。
    private func schedulePomodoroPhaseNotification(phase: PomodoroPhase, endDate: Date, taskTitle: String) {
        guard notificationsEnabled, notificationPermissionGranted, endDate > Date() else { return }
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
        content.sound = soundsEnabled ? .default : nil
        var components = beijingCalendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: endDate)
        components.calendar = beijingCalendar
        components.timeZone = beijingTimeZone
        let request = UNNotificationRequest(
            identifier: Self.pomodoroNotificationIdentifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
        pendingPomodoroNotificationIDs = [Self.pomodoroNotificationIdentifier]
        UNUserNotificationCenter.current().add(request)
    }

    private func cancelPomodoroNotifications() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [
            Self.pomodoroNotificationIdentifier
        ])
        pendingPomodoroNotificationIDs.removeAll()
    }

    /// 取消应用排入队列的全部通知（番茄钟 + 倒计时）。
    private func cancelAllScheduledNotifications() {
        notificationRescheduleGeneration &+= 1
        let generation = notificationRescheduleGeneration
        let center = UNUserNotificationCenter.current()
        var ids = Set(pendingPomodoroNotificationIDs)
        ids.insert(Self.pomodoroNotificationIdentifier)
        ids.formUnion(items.map { Self.countdownNotificationIdentifier(for: $0) })
        center.removePendingNotificationRequests(withIdentifiers: Array(ids))
        pendingPomodoroNotificationIDs.removeAll()

        // items 里已经找不到刚删除或被备份替换掉的目标，必须从系统队列按前缀清理。
        Task { @MainActor [weak self] in
            let identifiers: [String] = await withCheckedContinuation { continuation in
                center.getPendingNotificationRequests { requests in
                    continuation.resume(returning: requests.map(\.identifier))
                }
            }
            guard let self, generation == self.notificationRescheduleGeneration else { return }
            let managedIDs = identifiers.filter(TimeSlotNotificationIdentifier.isManaged)
            if !managedIDs.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: managedIDs)
            }
        }
    }

    /// 根据当前状态重建全部通知（倒计时 + 运行中的番茄钟阶段）。
    private func rescheduleAllNotifications() {
        notificationRescheduleGeneration &+= 1
        let generation = notificationRescheduleGeneration
        let center = UNUserNotificationCenter.current()

        Task { @MainActor [weak self] in
            let identifiers: [String] = await withCheckedContinuation { continuation in
                center.getPendingNotificationRequests { requests in
                    continuation.resume(returning: requests.map(\.identifier))
                }
            }
            guard let self, generation == self.notificationRescheduleGeneration else { return }

            let managedIDs = identifiers.filter(TimeSlotNotificationIdentifier.isManaged)
            if !managedIDs.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: managedIDs)
            }
            self.pendingPomodoroNotificationIDs.removeAll()

            guard self.notificationsEnabled, self.notificationPermissionGranted else { return }
            let now = Date()
            for item in self.items where CountdownNotificationPolicy.shouldSchedule(item: item, at: now) {
                self.scheduleCountdownNotification(for: item)
            }
            if self.pomodoro.isRunning,
               let endDate = self.pomodoro.endDate,
               endDate > now {
                self.schedulePomodoroPhaseNotification(
                    phase: self.pomodoro.phase,
                    endDate: endDate,
                    taskTitle: self.pomodoro.taskTitle
                )
            }
        }
    }

    private func requestNotificationPermissionIfNeeded() {
        updateNotificationPermission(requestIfNeeded: true)
    }

    private func updateNotificationPermission(requestIfNeeded: Bool, forceRequest: Bool = false) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            switch settings.authorizationStatus {
            case .notDetermined:
                self.notificationPermissionState = .notDetermined
                guard requestIfNeeded || forceRequest else { return }
                let hasActiveTimer = self.items.contains { item in
                    CountdownNotificationPolicy.shouldSchedule(item: item, at: Date())
                } || self.pomodoro.isRunning
                guard forceRequest || hasActiveTimer else { return }
                let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
                self.notificationPermissionState = granted ? .authorized : .denied
                self.notificationPermissionGranted = granted
                if granted { self.rescheduleAllNotifications() }
            case .authorized, .provisional, .ephemeral:
                let state: NotificationPermissionState = settings.authorizationStatus == .provisional
                    ? .provisional
                    : .authorized
                self.notificationPermissionState = state
                self.notificationPermissionGranted = true
                self.rescheduleAllNotifications()
            case .denied:
                self.notificationPermissionState = .denied
                self.notificationPermissionGranted = false
            default:
                self.notificationPermissionState = .denied
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
        content.sound = soundsEnabled ? .default : nil
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
        var didCompleteCountdown = false
        for item in items where item.pausedRemaining == nil && !countdownCompletionPlayed.contains(item.id) {
            guard item.remaining(at: date) <= 0 else { continue }
            countdownCompletionPlayed.insert(item.id)
            didCompleteCountdown = true
            guard abs(date.timeIntervalSince(item.targetDate)) <= 30 else { continue }
            if !notificationPermissionGranted && soundsEnabled {
                NSSound(named: "Glass")?.play()
            }
        }
        // 倒计时完成后更新 active/completed 筛选和详情状态；只在状态跃迁时通知一次。
        if didCompleteCountdown {
            reloadDesktopWidgetNow()
            objectWillChange.send()
        }
    }
}
