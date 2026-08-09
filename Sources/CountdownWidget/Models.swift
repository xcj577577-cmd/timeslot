import Foundation

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
        self.title = title
        self.targetDate = targetDate
        self.colorHex = colorHex
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
        title = try container.decode(String.self, forKey: .title)
        targetDate = try container.decode(Date.self, forKey: .targetDate)
        colorHex = try container.decodeIfPresent(String.self, forKey: .colorHex) ?? "#2C8C7C"
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        totalDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .totalDuration)
            ?? max(1, targetDate.timeIntervalSince(createdAt))
        pausedRemaining = try container.decodeIfPresent(TimeInterval.self, forKey: .pausedRemaining)
    }
}

/// 倒计时完成通知的纯决策逻辑，独立成函数便于测试：
/// 只有「未暂停且仍在倒计时中」的目标才需要安排通知。
enum CountdownNotificationPolicy {
    static func shouldSchedule(item: CountdownItem, at date: Date) -> Bool {
        item.pausedRemaining == nil && item.remaining(at: date) > 0
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
    case last7Days
    case thisMonth
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .today: return "今天"
        case .last7Days: return "近 7 天"
        case .thisMonth: return "本月"
        case .custom: return "自定义"
        }
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
        self.title = title
        self.createdAt = createdAt
        self.colorHex = colorHex
    }

    enum CodingKeys: String, CodingKey {
        case id, title, createdAt, colorHex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        colorHex = try container.decodeIfPresent(String.self, forKey: .colorHex) ?? ""
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
        taskTitle = try container.decodeIfPresent(String.self, forKey: .taskTitle) ?? "专注当前任务"
        phase = try container.decodeIfPresent(PomodoroPhase.self, forKey: .phase) ?? .focus
        focusMinutes = try container.decodeIfPresent(Int.self, forKey: .focusMinutes) ?? 25
        shortBreakMinutes = try container.decodeIfPresent(Int.self, forKey: .shortBreakMinutes) ?? 5
        longBreakMinutes = try container.decodeIfPresent(Int.self, forKey: .longBreakMinutes) ?? 15
        // 防御性钳制：备份/旧数据里可能出现 0 或负值，
        // % roundsBeforeLongBreak 会除零崩溃，0..<负数 的 ForEach 同样会 trap。
        roundsBeforeLongBreak = min(8, max(2, try container.decodeIfPresent(Int.self, forKey: .roundsBeforeLongBreak) ?? 4))
        focusMinutes = min(180, max(1, try container.decodeIfPresent(Int.self, forKey: .focusMinutes) ?? 25))
        shortBreakMinutes = min(60, max(1, try container.decodeIfPresent(Int.self, forKey: .shortBreakMinutes) ?? 5))
        longBreakMinutes = min(120, max(1, try container.decodeIfPresent(Int.self, forKey: .longBreakMinutes) ?? 15))
        weeklyFocusGoalMinutes = try container.decodeIfPresent(Int.self, forKey: .weeklyFocusGoalMinutes)
            ?? 10 * 60
        completedFocusSessions = try container.decodeIfPresent(Int.self, forKey: .completedFocusSessions) ?? 0
        isRunning = try container.decodeIfPresent(Bool.self, forKey: .isRunning) ?? false
        endDate = try container.decodeIfPresent(Date.self, forKey: .endDate)
        pausedRemaining = try container.decodeIfPresent(TimeInterval.self, forKey: .pausedRemaining)
            ?? TimeInterval(focusMinutes * 60)
        sessionStartedAt = try container.decodeIfPresent(Date.self, forKey: .sessionStartedAt)
        activeStartedAt = try container.decodeIfPresent(Date.self, forKey: .activeStartedAt)
        accumulatedElapsed = try container.decodeIfPresent(TimeInterval.self, forKey: .accumulatedElapsed) ?? 0
        stopwatchRunning = try container.decodeIfPresent(Bool.self, forKey: .stopwatchRunning) ?? false
        stopwatchSessionStartedAt = try container.decodeIfPresent(Date.self, forKey: .stopwatchSessionStartedAt)
        stopwatchActiveStartedAt = try container.decodeIfPresent(Date.self, forKey: .stopwatchActiveStartedAt)
        stopwatchAccumulated = try container.decodeIfPresent(TimeInterval.self, forKey: .stopwatchAccumulated) ?? 0
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
    var schemaVersion: Int = 1
    let items: [CountdownItem]
    let pomodoro: PomodoroState
    let history: [PomodoroSessionRecord]
    let tasks: [PomodoroTask]
    let displayMode: String
    let timeUnit: String
    let exportedAt: Date
}
