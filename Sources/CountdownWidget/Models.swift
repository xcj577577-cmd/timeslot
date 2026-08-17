import Foundation

/// Hex 颜色的唯一解析入口。数据文件和备份都可能被手动修改，任何非法值都必须
/// 回落到品牌色，不能让主应用与小组件各自解析出不同结果。
enum ColorHex {
    static let fallback = "#2C8C7C"

    static func isValid(_ value: String) -> Bool {
        rgba(from: value) != nil
    }

    static func normalized(_ value: String, fallback: String = ColorHex.fallback) -> String {
        guard let rgba = rgba(from: value) else { return fallback }
        let red = Int((rgba.red * 255).rounded())
        let green = Int((rgba.green * 255).rounded())
        let blue = Int((rgba.blue * 255).rounded())
        if rgba.alpha < 0.999 {
            let alpha = Int((rgba.alpha * 255).rounded())
            return String(format: "#%02X%02X%02X%02X", red, green, blue, alpha)
        }
        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    static func rgba(from value: String) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat)? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        let validDigits = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        guard digits.count == 6 || digits.count == 8,
              digits.unicodeScalars.allSatisfy(validDigits.contains) else {
            return nil
        }
        var raw: UInt64 = 0
        guard Scanner(string: digits).scanHexInt64(&raw) else { return nil }
        if digits.count == 6 {
            return (
                CGFloat((raw >> 16) & 0xFF) / 255,
                CGFloat((raw >> 8) & 0xFF) / 255,
                CGFloat(raw & 0xFF) / 255,
                1
            )
        }
        return (
            CGFloat((raw >> 24) & 0xFF) / 255,
            CGFloat((raw >> 16) & 0xFF) / 255,
            CGFloat((raw >> 8) & 0xFF) / 255,
            CGFloat(raw & 0xFF) / 255
        )
    }
}

struct CountdownItem: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var targetDate: Date
    var colorHex: String
    var isPinned: Bool
    var createdAt: Date
    var totalDuration: TimeInterval
    var pausedRemaining: TimeInterval?

    init(id: UUID = UUID(), title: String, targetDate: Date, colorHex: String = "#2C8C7C", isPinned: Bool = false) {
        self.id = id
        self.title = Self.normalizedTitle(title)
        self.targetDate = targetDate
        self.colorHex = ColorHex.normalized(colorHex)
        self.isPinned = isPinned
        self.createdAt = Date()
        self.totalDuration = max(1, targetDate.timeIntervalSince(createdAt))
        self.pausedRemaining = nil
    }

    var isPaused: Bool {
        pausedRemaining != nil
    }

    func remaining(at date: Date) -> TimeInterval {
        max(0, pausedRemaining ?? targetDate.timeIntervalSince(date))
    }

    enum CodingKeys: String, CodingKey {
        case id, title, targetDate, colorHex, isPinned, createdAt, totalDuration, pausedRemaining
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = Self.normalizedTitle(try container.decode(String.self, forKey: .title))
        targetDate = try container.decode(Date.self, forKey: .targetDate)
        colorHex = ColorHex.normalized(
            try container.decodeIfPresent(String.self, forKey: .colorHex) ?? ColorHex.fallback
        )
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        let decodedDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .totalDuration)
        totalDuration = decodedDuration?.isFinite == true
            ? max(1, decodedDuration ?? 1)
            : max(1, targetDate.timeIntervalSince(createdAt))
        let decodedPaused = try container.decodeIfPresent(TimeInterval.self, forKey: .pausedRemaining)
        pausedRemaining = decodedPaused?.isFinite == true ? max(0, decodedPaused ?? 0) : nil
    }

    static func normalizedTitle(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return String((trimmed.isEmpty ? "未命名倒计时" : trimmed).prefix(80))
    }
}

/// 区分“从未保存”“明确保存为空”和“存档损坏”。空数组是合法用户状态，
/// 绝不能和首次启动混为一谈，否则用户删完后下次启动会重新出现示例数据。
enum CountdownItemsStorageResolution: Equatable {
    case missing
    case decoded([CountdownItem])
    case corrupted
}

enum CountdownItemsStoragePolicy {
    static func resolve(_ data: Data?) -> CountdownItemsStorageResolution {
        guard let data else { return .missing }
        do {
            return .decoded(try JSONDecoder().decode([CountdownItem].self, from: data))
        } catch {
            return .corrupted
        }
    }
}

/// 主应用与小组件共用的本地存储版本。
///
/// v1 是没有显式版本标记的 UserDefaults JSON；v2 保留原有键和数据格式，
/// 但会先生成迁移快照，再写入规范化后的数据与原子小组件状态。这样不必为了
/// 跨进程共享而贸然切换到 SwiftData，同时也让未来字段迁移有明确的落点。
enum LocalStorageMigration {
    static let currentSchemaVersion = 2

    static func needsMigration(storedVersion: Int?) -> Bool {
        guard let storedVersion else { return true }
        return storedVersion < currentSchemaVersion
    }
}

enum StorageMigrationState: Equatable {
    case current
    case migrated(from: Int?)
    case pending(String)

    var title: String {
        switch self {
        case .current: return "本地数据正常"
        case .migrated: return "本地数据已升级"
        case .pending: return "本地数据等待升级"
        }
    }

    var subtitle: String {
        switch self {
        case .current:
            return "当前数据格式与小组件共享状态一致"
        case .migrated(let version):
            if let version {
                return "已从旧版格式 " + String(version) + " 安全整理，原始迁移快照已保留"
            }
            return "已完成首次数据整理，原始迁移快照已保留"
        case .pending(let message):
            return message
        }
    }
}

/// 倒计时完成通知的纯决策逻辑，独立成函数便于测试：
/// 只有「未暂停且仍在倒计时中」的目标才需要安排通知。
enum CountdownNotificationPolicy {
    static func shouldSchedule(item: CountdownItem, at date: Date) -> Bool {
        item.pausedRemaining == nil && item.remaining(at: date) > 0
    }
}

enum NotificationPermissionState: Equatable {
    case checking
    case notDetermined
    case authorized
    case provisional
    case denied

    var title: String {
        switch self {
        case .checking: return "正在检查系统通知权限"
        case .notDetermined: return "尚未允许系统通知"
        case .authorized: return "系统通知已允许"
        case .provisional: return "系统通知已临时允许"
        case .denied: return "系统通知已关闭"
        }
    }

    var detail: String {
        switch self {
        case .checking: return "正在读取 macOS 的通知设置"
        case .notDetermined: return "允许后，倒计时和番茄钟才能在后台提醒你"
        case .authorized: return "倒计时和番茄钟可以在后台提醒你"
        case .provisional: return "通知可能以较低打扰方式显示"
        case .denied: return "请在系统设置中重新打开时隙的通知"
        }
    }

    var systemImage: String {
        switch self {
        case .checking: return "ellipsis.circle"
        case .notDetermined: return "bell.badge"
        case .authorized, .provisional: return "checkmark.circle.fill"
        case .denied: return "bell.slash"
        }
    }
}

enum UndoableStoreAction: Equatable {
    case countdownDeleted(title: String)
    case pomodoroHistoryCleared(count: Int)

    var message: String {
        switch self {
        case .countdownDeleted(let title): return "已删除「\(title)」"
        case .pomodoroHistoryCleared(let count): return "已清空 \(count) 条阶段记录"
        }
    }
}

/// 时隙只管理自己的通知标识；清理旧请求时不能误删其他应用或未来系统请求。
enum TimeSlotNotificationIdentifier {
    static let pomodoroPhaseEnd = "pomodoro.phase.end"

    static func countdownCompletion(for id: UUID) -> String {
        "countdown.completion.\(id.uuidString)"
    }

    static func isManaged(_ identifier: String) -> Bool {
        identifier == pomodoroPhaseEnd
            || identifier.hasPrefix("pomodoro.phase.end.")
            || identifier.hasPrefix("countdown.completion.")
    }
}

enum PomodoroPhase: String, Codable, CaseIterable {
    case focus
    case shortBreak
    case longBreak

    var title: String {
        switch self {
        case .focus: return "专注"
        case .shortBreak: return "短休息"
        case .longBreak: return "长休息"
        }
    }

    var icon: String {
        switch self {
        case .focus: return "brain.head.profile"
        case .shortBreak: return "cup.and.saucer.fill"
        case .longBreak: return "leaf.fill"
        }
    }

    var colorHex: String {
        switch self {
        case .focus: return "#D86F52"
        case .shortBreak: return "#2C8C7C"
        case .longBreak: return "#5A78B8"
        }
    }
}

/// 常用时长预设。Stepper 一次只动 1 分钟，从 25 改到 50 要点 25 下，
/// 所以主页的「当前节奏」和设置弹窗都直接给这些值。
enum PomodoroPresets {
    static let focus = [15, 25, 30, 45, 50, 60, 90]
    static let shortBreak = [3, 5, 10, 15]
    static let longBreak = [10, 15, 20, 30]
    static let rounds = [2, 3, 4, 5, 6]
}

enum PomodoroRecordStatus: String, Codable {
    case completed
    case skipped
    case interrupted
    case stopped
    case stopwatch

    var title: String {
        switch self {
        case .completed: return "已完成"
        case .skipped: return "已跳过"
        case .interrupted: return "已中断"
        case .stopped: return "已停止"
        case .stopwatch: return "正计时"
        }
    }
}

enum PomodoroHistoryRange: String, CaseIterable, Identifiable {
    case all
    case today
    case week
    case last7Days
    case thisMonth
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .today: return "今天"
        case .week: return "按周"
        case .last7Days: return "近 7 天"
        case .thisMonth: return "本月"
        case .custom: return "自定义"
        }
    }
}

struct PomodoroHistoryBounds: Equatable {
    let start: Date
    let end: Date
}

enum PomodoroHistoryRangePolicy {
    static func weekStart(containing date: Date, calendar: Calendar = beijingCalendar) -> Date {
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day)
        let daysSinceMonday = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -daysSinceMonday, to: day) ?? day
    }

    static func bounds(
        for range: PomodoroHistoryRange,
        now: Date,
        selectedWeekStart: Date,
        customStart: Date,
        customEnd: Date,
        calendar: Calendar = beijingCalendar
    ) -> PomodoroHistoryBounds? {
        switch range {
        case .all:
            return nil
        case .today:
            let start = calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: .day, value: 1, to: start)
                ?? start.addingTimeInterval(86_400)
            return PomodoroHistoryBounds(start: start, end: end)
        case .week:
            let start = weekStart(containing: selectedWeekStart, calendar: calendar)
            let end = calendar.date(byAdding: .day, value: 7, to: start)
                ?? start.addingTimeInterval(7 * 86_400)
            return PomodoroHistoryBounds(start: start, end: end)
        case .last7Days:
            let today = calendar.startOfDay(for: now)
            let start = calendar.date(byAdding: .day, value: -6, to: today) ?? today
            let end = calendar.date(byAdding: .day, value: 1, to: today)
                ?? today.addingTimeInterval(86_400)
            return PomodoroHistoryBounds(start: start, end: end)
        case .thisMonth:
            let start = calendar.date(
                from: calendar.dateComponents([.year, .month], from: now)
            ) ?? calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: .month, value: 1, to: start)
                ?? start.addingTimeInterval(31 * 86_400)
            return PomodoroHistoryBounds(start: start, end: end)
        case .custom:
            let start = calendar.startOfDay(for: min(customStart, customEnd))
            let lastDay = calendar.startOfDay(for: max(customStart, customEnd))
            let end = calendar.date(byAdding: .day, value: 1, to: lastDay)
                ?? lastDay.addingTimeInterval(86_400)
            return PomodoroHistoryBounds(start: start, end: end)
        }
    }

    static func availableWeekStarts(
        recordDates: [Date],
        now: Date,
        calendar: Calendar = beijingCalendar
    ) -> [Date] {
        var starts = Set(recordDates.map { weekStart(containing: $0, calendar: calendar) })
        starts.insert(weekStart(containing: now, calendar: calendar))
        return starts.sorted(by: >)
    }
}

/// 任务配色。统计里每个任务用固定的一种颜色，图表、图例、按任务分布和历史行都取这里。
enum PomodoroTaskPalette {
    static let colorHexes = [
        "#2C8C7C", "#D86F52", "#5A78B8", "#B07A3A",
        "#7B5EA7", "#4C9A5A", "#C2557A", "#3E8FA8"
    ]

    static let fallbackTitle = "专注当前任务"

    static func normalized(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallbackTitle : trimmed
    }

    /// 新任务取当前用得最少的那个颜色，因此前 8 个任务必然互不相同，之后才开始轮转。
    /// （最早写成「按标题哈希取色」，结果 6 个任务里 4 个撞色，等于没分色。）
    static func nextColorHex(after existing: [String]) -> String {
        var counts: [String: Int] = [:]
        for hex in existing where !hex.isEmpty {
            counts[hex, default: 0] += 1
        }
        var best = colorHexes[0]
        var bestCount = Int.max
        for hex in colorHexes {           // 按调色板顺序遍历，同分时天然取靠前的
            let count = counts[hex] ?? 0
            if count < bestCount {
                bestCount = count
                best = hex
            }
        }
        return best
    }

    /// 历史里已被删除的任务不在任务列表里、没有登记颜色，用标题推一个稳定值兜底。
    /// 不能用 Swift 的 hashValue——它每个进程重新加盐，配色会每次启动都变。
    static func fallbackColorHex(for title: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in normalized(title).utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return colorHexes[Int(hash % UInt64(colorHexes.count))]
    }
}

struct PomodoroDailyFocusPoint: Identifiable {
    let day: Date
    let taskTitle: String
    let duration: TimeInterval

    var id: String { "\(day.timeIntervalSinceReferenceDate)#\(taskTitle)" }
}

struct PomodoroTask: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    let createdAt: Date
    /// 统计里这个任务的固定颜色。空串代表尚未分配（旧数据），载入时由 store 补齐。
    var colorHex: String

    init(id: UUID = UUID(), title: String, createdAt: Date = Date(), colorHex: String = "") {
        self.id = id
        self.title = String(PomodoroTaskPalette.normalized(title).prefix(40))
        self.createdAt = createdAt
        self.colorHex = colorHex.isEmpty ? "" : ColorHex.normalized(colorHex)
    }

    enum CodingKeys: String, CodingKey {
        case id, title, createdAt, colorHex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = String(PomodoroTaskPalette.normalized(try container.decode(String.self, forKey: .title)).prefix(40))
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        let decodedColor = try container.decodeIfPresent(String.self, forKey: .colorHex) ?? ""
        colorHex = decodedColor.isEmpty ? "" : ColorHex.normalized(decodedColor)
    }
}

struct PomodoroSessionRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let phase: PomodoroPhase
    let taskTitle: String
    let plannedDuration: TimeInterval
    let actualDuration: TimeInterval
    let startedAt: Date
    let endedAt: Date
    let status: PomodoroRecordStatus

    init(
        id: UUID = UUID(),
        phase: PomodoroPhase,
        taskTitle: String,
        plannedDuration: TimeInterval,
        actualDuration: TimeInterval,
        startedAt: Date,
        endedAt: Date,
        status: PomodoroRecordStatus
    ) {
        self.id = id
        self.phase = phase
        self.taskTitle = taskTitle
        self.plannedDuration = plannedDuration
        self.actualDuration = actualDuration
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.status = status
    }
}

struct PomodoroState: Codable, Equatable {
    var taskTitle = "专注当前任务"
    var phase: PomodoroPhase = .focus
    var focusMinutes = 25
    var shortBreakMinutes = 5
    var longBreakMinutes = 15
    var roundsBeforeLongBreak = 4
    /// 每周专注目标，单位为分钟。默认 10 小时，作为小组件的可读起点。
    var weeklyFocusGoalMinutes = 10 * 60
    var completedFocusSessions = 0
    var isRunning = false
    var endDate: Date?
    var pausedRemaining: TimeInterval = 25 * 60
    var sessionStartedAt: Date?
    var activeStartedAt: Date?
    var accumulatedElapsed: TimeInterval = 0
    var stopwatchRunning = false
    var stopwatchSessionStartedAt: Date?
    var stopwatchActiveStartedAt: Date?
    var stopwatchAccumulated: TimeInterval = 0

    enum CodingKeys: String, CodingKey {
        case taskTitle, phase, focusMinutes, shortBreakMinutes, longBreakMinutes
        case roundsBeforeLongBreak, weeklyFocusGoalMinutes, completedFocusSessions, isRunning, endDate
        case pausedRemaining, sessionStartedAt, activeStartedAt, accumulatedElapsed
        case stopwatchRunning, stopwatchSessionStartedAt, stopwatchActiveStartedAt, stopwatchAccumulated
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        taskTitle = String(PomodoroTaskPalette.normalized(
            try container.decodeIfPresent(String.self, forKey: .taskTitle) ?? "专注当前任务"
        ).prefix(40))
        phase = try container.decodeIfPresent(PomodoroPhase.self, forKey: .phase) ?? .focus
        // 防御性钳制：备份/旧数据里可能出现 0 或负值，
        // % roundsBeforeLongBreak 会除零崩溃，0..<负数 的 ForEach 同样会 trap。
        roundsBeforeLongBreak = min(8, max(2, try container.decodeIfPresent(Int.self, forKey: .roundsBeforeLongBreak) ?? 4))
        focusMinutes = min(120, max(1, try container.decodeIfPresent(Int.self, forKey: .focusMinutes) ?? 25))
        shortBreakMinutes = min(30, max(1, try container.decodeIfPresent(Int.self, forKey: .shortBreakMinutes) ?? 5))
        longBreakMinutes = min(60, max(1, try container.decodeIfPresent(Int.self, forKey: .longBreakMinutes) ?? 15))
        weeklyFocusGoalMinutes = min(
            168 * 60,
            max(60, try container.decodeIfPresent(Int.self, forKey: .weeklyFocusGoalMinutes) ?? 10 * 60)
        )
        completedFocusSessions = max(0, try container.decodeIfPresent(Int.self, forKey: .completedFocusSessions) ?? 0)
        isRunning = try container.decodeIfPresent(Bool.self, forKey: .isRunning) ?? false
        endDate = try container.decodeIfPresent(Date.self, forKey: .endDate)
        let decodedPaused = try container.decodeIfPresent(TimeInterval.self, forKey: .pausedRemaining)
            ?? TimeInterval(focusMinutes * 60)
        pausedRemaining = decodedPaused.isFinite ? decodedPaused : TimeInterval(focusMinutes * 60)
        sessionStartedAt = try container.decodeIfPresent(Date.self, forKey: .sessionStartedAt)
        activeStartedAt = try container.decodeIfPresent(Date.self, forKey: .activeStartedAt)
        let decodedAccumulated = try container.decodeIfPresent(TimeInterval.self, forKey: .accumulatedElapsed) ?? 0
        accumulatedElapsed = decodedAccumulated.isFinite ? decodedAccumulated : 0
        stopwatchRunning = try container.decodeIfPresent(Bool.self, forKey: .stopwatchRunning) ?? false
        stopwatchSessionStartedAt = try container.decodeIfPresent(Date.self, forKey: .stopwatchSessionStartedAt)
        stopwatchActiveStartedAt = try container.decodeIfPresent(Date.self, forKey: .stopwatchActiveStartedAt)
        let decodedStopwatch = try container.decodeIfPresent(TimeInterval.self, forKey: .stopwatchAccumulated) ?? 0
        stopwatchAccumulated = decodedStopwatch.isFinite ? decodedStopwatch : 0
        normalizeForRuntime()
    }

    mutating func normalizeForRuntime() {
        focusMinutes = min(120, max(1, focusMinutes))
        shortBreakMinutes = min(30, max(1, shortBreakMinutes))
        longBreakMinutes = min(60, max(1, longBreakMinutes))
        roundsBeforeLongBreak = min(8, max(2, roundsBeforeLongBreak))
        weeklyFocusGoalMinutes = min(168 * 60, max(60, weeklyFocusGoalMinutes))
        completedFocusSessions = max(0, completedFocusSessions)
        taskTitle = String(PomodoroTaskPalette.normalized(taskTitle).prefix(40))

        let phaseDuration = duration(for: phase)
        pausedRemaining = min(phaseDuration, max(0, pausedRemaining.isFinite ? pausedRemaining : phaseDuration))
        accumulatedElapsed = min(phaseDuration, max(0, accumulatedElapsed.isFinite ? accumulatedElapsed : 0))
        stopwatchAccumulated = max(0, stopwatchAccumulated.isFinite ? stopwatchAccumulated : 0)

        if isRunning, endDate == nil {
            isRunning = false
            activeStartedAt = nil
        }
        if stopwatchRunning, stopwatchActiveStartedAt == nil {
            stopwatchRunning = false
        }
        if isRunning, isStopwatchActive {
            if stopwatchRunning {
                isRunning = false
                endDate = nil
                sessionStartedAt = nil
                activeStartedAt = nil
                accumulatedElapsed = 0
                pausedRemaining = phaseDuration
            } else {
                stopwatchSessionStartedAt = nil
                stopwatchActiveStartedAt = nil
                stopwatchAccumulated = 0
            }
        }
    }

    func duration(for phase: PomodoroPhase) -> TimeInterval {
        switch phase {
        case .focus: return TimeInterval(focusMinutes * 60)
        case .shortBreak: return TimeInterval(shortBreakMinutes * 60)
        case .longBreak: return TimeInterval(longBreakMinutes * 60)
        }
    }

    func remaining(at date: Date) -> TimeInterval {
        let phaseDuration = duration(for: phase)
        guard isRunning, let endDate else {
            return min(phaseDuration, max(0, pausedRemaining))
        }
        return min(phaseDuration, max(0, endDate.timeIntervalSince(date)))
    }

    func elapsed(at date: Date) -> TimeInterval {
        let activeElapsed: TimeInterval
        if isRunning, let activeStartedAt {
            activeElapsed = max(0, date.timeIntervalSince(activeStartedAt))
        } else {
            activeElapsed = 0
        }
        return min(duration(for: phase), max(0, accumulatedElapsed + activeElapsed))
    }

    var isStopwatchActive: Bool {
        stopwatchRunning || stopwatchSessionStartedAt != nil || stopwatchAccumulated > 0
    }

    func stopwatchElapsed(at date: Date) -> TimeInterval {
        let activeElapsed: TimeInterval
        if stopwatchRunning, let stopwatchActiveStartedAt {
            activeElapsed = max(0, date.timeIntervalSince(stopwatchActiveStartedAt))
        } else {
            activeElapsed = 0
        }
        return max(0, stopwatchAccumulated + activeElapsed)
    }

    /// 系统可能在 endDate 之后很久才把 App 唤醒；历史仍应截止在计划结束时刻。
    func completionDate(whenObservedAt date: Date) -> Date {
        min(date, endDate ?? date)
    }
}

enum TimeBookSection: String, CaseIterable {
    case countdown
    case pomodoro
    case settings
}

enum WidgetSyncState: Equatable {
    case checking
    case ready(Date)
    case unavailable
    case failed(String)
}

/// 桌面小组件显示什么。原来只有二选一，现在多一个「两者」同时显示。
/// 原始值要和小组件扩展里读取的字符串保持一致。
enum WidgetDisplayMode: String, CaseIterable, Identifiable {
    case countdown
    case pomodoro
    case both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .countdown: return "倒计时"
        case .pomodoro: return "番茄钟"
        case .both: return "两者"
        }
    }
}

/// 番茄钟工作区里的计时方式：倒计时番茄钟，或自由累计的「正计时」。
enum PomodoroTimerMode: String, CaseIterable, Identifiable {
    case countdown
    case stopwatch

    var id: String { rawValue }

    var title: String {
        switch self {
        case .countdown: return "番茄钟"
        case .stopwatch: return "正计时"
        }
    }

    var icon: String {
        switch self {
        case .countdown: return "timer"
        case .stopwatch: return "stopwatch.fill"
        }
    }
}

// MARK: - 数据备份

/// 完整数据备份（导出/恢复用）。schemaVersion 预留给未来迁移。
struct BackupPayload: Codable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let items: [CountdownItem]
    let pomodoro: PomodoroState
    let history: [PomodoroSessionRecord]
    let tasks: [PomodoroTask]
    let displayMode: String
    let timeUnit: String
    let exportedAt: Date

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        items: [CountdownItem],
        pomodoro: PomodoroState,
        history: [PomodoroSessionRecord],
        tasks: [PomodoroTask],
        displayMode: String,
        timeUnit: String,
        exportedAt: Date
    ) {
        self.schemaVersion = schemaVersion
        self.items = items
        self.pomodoro = pomodoro
        self.history = history
        self.tasks = tasks
        self.displayMode = displayMode
        self.timeUnit = timeUnit
        self.exportedAt = exportedAt
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, items, pomodoro, history, tasks, displayMode, timeUnit, exportedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        items = try container.decode([CountdownItem].self, forKey: .items)
        pomodoro = try container.decode(PomodoroState.self, forKey: .pomodoro)
        history = try container.decodeIfPresent([PomodoroSessionRecord].self, forKey: .history) ?? []
        tasks = try container.decodeIfPresent([PomodoroTask].self, forKey: .tasks) ?? []
        displayMode = try container.decodeIfPresent(String.self, forKey: .displayMode) ?? "both"
        timeUnit = try container.decodeIfPresent(String.self, forKey: .timeUnit) ?? "auto"
        exportedAt = try container.decodeIfPresent(Date.self, forKey: .exportedAt) ?? Date()
    }
}

enum BackupValidationError: LocalizedError, Equatable {
    case fileTooLarge
    case unsupportedSchema(Int)
    case tooManyItems
    case tooManyRecords
    case tooManyTasks

    var errorDescription: String? {
        switch self {
        case .fileTooLarge: return "备份文件过大，无法安全导入。"
        case .unsupportedSchema(let version):
            if version > BackupPayload.currentSchemaVersion {
                return "这个备份来自更高版本（格式 \(version)），请先更新时隙。"
            }
            return "无法识别这个备份的格式（格式 \(version)）。"
        case .tooManyItems: return "备份中的倒计时数量异常。"
        case .tooManyRecords: return "备份中的阶段记录数量异常。"
        case .tooManyTasks: return "备份中的任务数量异常。"
        }
    }
}

enum BackupOperationError: LocalizedError {
    case cannotEncodeCurrentData

    var errorDescription: String? {
        switch self {
        case .cannotEncodeCurrentData:
            return "无法创建导入前的安全备份，当前数据没有被更改。"
        }
    }
}

enum BackupValidationPolicy {
    static let maximumFileSize = 20 * 1_024 * 1_024
    static let maximumItems = 5_000
    static let maximumHistoryRecords = 50_000
    static let maximumTasks = 1_000

    static func validate(dataSize: Int, payload: BackupPayload) throws {
        guard dataSize <= maximumFileSize else { throw BackupValidationError.fileTooLarge }
        guard (1...BackupPayload.currentSchemaVersion).contains(payload.schemaVersion) else {
            throw BackupValidationError.unsupportedSchema(payload.schemaVersion)
        }
        guard payload.items.count <= maximumItems else { throw BackupValidationError.tooManyItems }
        guard payload.history.count <= maximumHistoryRecords else { throw BackupValidationError.tooManyRecords }
        guard payload.tasks.count <= maximumTasks else { throw BackupValidationError.tooManyTasks }
    }
}
