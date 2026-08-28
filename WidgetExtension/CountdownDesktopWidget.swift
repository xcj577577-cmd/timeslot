import SwiftUI
import WidgetKit
import AppIntents

private let beijingTimeZone = TimeZone(identifier: "Asia/Shanghai")
    ?? TimeZone(secondsFromGMT: 8 * 60 * 60)
    ?? .current
private let beijingLocale = Locale(identifier: "zh_CN")

private var beijingCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = beijingTimeZone
    calendar.locale = beijingLocale
    return calendar
}

private let sharedDefaultsName = "4FKFDX48HX.com.xianz.countdownwidget.shared"
private let sharedItemsKey = "countdownItems"
private let sharedPomodoroKey = "pomodoroState"
private let sharedPomodoroHistoryKey = "pomodoroHistory"
private let widgetDisplayModeKey = "widgetDisplayMode"
// 石墨灰主题（与主应用 ColorPreset.graphite 一致），金色仅保留给品牌楔形。
private let widgetAccentLightHex = "#5C5C66"
private let widgetAccentDarkHex = "#A8A8B0"
private let widgetBreakLightHex = "#6B6B74"
private let widgetBreakDarkHex = "#8E8E96"
private let widgetLongBreakLightHex = "#4F4F58"
private let widgetLongBreakDarkHex = "#7A7A82"
private let widgetBrandInkHex = "#0A1926"
private let widgetBrandDeepTealHex = "#103D3B"
private let widgetBrandTealHex = "#35B79F"
private let widgetBrandMintHex = "#8CE4D0"
private let widgetBrandGoldHex = "#E8C27A"

private enum WidgetColorHex {
    static let fallback = "#2C8C7C"

    static func normalized(_ value: String) -> String {
        guard let components = components(from: value) else { return fallback }
        let red = Int((components.red * 255).rounded())
        let green = Int((components.green * 255).rounded())
        let blue = Int((components.blue * 255).rounded())
        if components.alpha < 0.999 {
            return String(
                format: "#%02X%02X%02X%02X",
                red,
                green,
                blue,
                Int((components.alpha * 255).rounded())
            )
        }
        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    static func components(
        from value: String
    ) -> (red: Double, green: Double, blue: Double, alpha: Double)? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        let validDigits = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        guard digits.count == 6 || digits.count == 8,
              digits.unicodeScalars.allSatisfy(validDigits.contains) else { return nil }
        var raw: UInt64 = 0
        guard Scanner(string: digits).scanHexInt64(&raw) else { return nil }
        if digits.count == 8 {
            return (
                Double((raw >> 24) & 0xFF) / 255,
                Double((raw >> 16) & 0xFF) / 255,
                Double((raw >> 8) & 0xFF) / 255,
                Double(raw & 0xFF) / 255
            )
        }
        return (
            Double((raw >> 16) & 0xFF) / 255,
            Double((raw >> 8) & 0xFF) / 255,
            Double(raw & 0xFF) / 255,
            1
        )
    }
}

/// App 图标在小组件里的微缩版本。保持同一组“错位时间带 + 金色时隙”几何，
/// 但删除小尺寸下无法辨认的高光与描边，确保 13pt 仍是一个清晰符号。
private struct WidgetBrandGlyph: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: widgetBrandInkHex), Color(hex: widgetBrandDeepTealHex)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: size * 0.06, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: widgetBrandMintHex), Color(hex: widgetBrandTealHex)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size * 0.34, height: size * 0.13)
                .offset(x: -size * 0.17, y: -size * 0.06)
                .widgetAccentable()

            RoundedRectangle(cornerRadius: size * 0.06, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: widgetBrandMintHex), Color(hex: widgetBrandTealHex)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size * 0.34, height: size * 0.13)
                .offset(x: size * 0.17, y: size * 0.06)
                .widgetAccentable()

            Path { path in
                path.move(to: CGPoint(x: size * 0.455, y: size * 0.39))
                path.addLine(to: CGPoint(x: size * 0.545, y: size * 0.48))
                path.addLine(to: CGPoint(x: size * 0.545, y: size * 0.61))
                path.addLine(to: CGPoint(x: size * 0.455, y: size * 0.52))
                path.closeSubpath()
            }
            .fill(Color(hex: widgetBrandGoldHex))
            .widgetAccentable()
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// 与主应用 TimeSlotWedge 同构。小组件是独立 target，几何必须在这里再写一遍。
private struct WidgetTimeSlotWedge: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.08))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.32))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - rect.height * 0.08))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - rect.height * 0.32))
        path.closeSubpath()
        return path
    }
}

private struct WidgetModeLabel: View {
    let title: String

    var body: some View {
        HStack(spacing: 5) {
            WidgetBrandGlyph(size: 13)
            Text(title)
                .font(.caption2.weight(.medium))
                .tracking(0.35)
        }
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}

private struct WidgetBackdrop: View {
    let accent: Color
    let family: WidgetFamily

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color(nsColor: .windowBackgroundColor)

            LinearGradient(
                colors: [accent.opacity(0.10), accent.opacity(0.02), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

/// 小组件专用精致进度条：浅色轨道 + 品牌渐变填充 + 柔和阴影。
/// 与客户端 TimeSlotProgressBar 同源设计，但更薄、不占用额外高度。
private struct WidgetProgressBar: View {
    let value: CGFloat
    let color: Color
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            let clamped = min(1, max(0, value))
            let width = max(0, proxy.size.width) * clamped
            let wedgeWidth = height * 0.7
            let wedgeHeight = height * 1.55
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [color, color.opacity(0.76)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: width)
                    .shadow(color: color.opacity(0.25), radius: 2, x: 0, y: 1)
                    .widgetAccentable()
            }
            .overlay(alignment: .leading) {
                if clamped > 0.04 {
                    WidgetTimeSlotWedge()
                        .fill(Color(hex: widgetBrandGoldHex))
                        .frame(width: wedgeWidth, height: wedgeHeight)
                        .offset(
                            x: min(
                                max(width - wedgeWidth * 0.55, 0),
                                max(0, proxy.size.width - wedgeWidth)
                            )
                        )
                        .widgetAccentable()
                }
            }
        }
        .frame(height: height)
    }
}

struct SharedCountdownItem: Codable, Identifiable {
    let id: UUID
    let title: String
    let targetDate: Date
    let colorHex: String
    let isPinned: Bool
    let createdAt: Date?
    let totalDuration: TimeInterval?
    let pausedRemaining: TimeInterval?

    func remaining(at date: Date) -> TimeInterval {
        max(0, pausedRemaining ?? targetDate.timeIntervalSince(date))
    }

    enum CodingKeys: String, CodingKey {
        case id, title, targetDate, colorHex, isPinned, createdAt, totalDuration, pausedRemaining
    }

    // 主 App 对 colorHex / isPinned 用的是 decodeIfPresent，说明存在缺字段的历史数据。
    // 这里若要求必填，整个数组会解码失败，小组件直接掉成空状态。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        let decodedTitle = try container.decode(String.self, forKey: .title)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        title = String((decodedTitle.isEmpty ? "未命名倒计时" : decodedTitle).prefix(80))
        targetDate = try container.decode(Date.self, forKey: .targetDate)
        colorHex = WidgetColorHex.normalized(
            try container.decodeIfPresent(String.self, forKey: .colorHex) ?? WidgetColorHex.fallback
        )
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        let decodedDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .totalDuration)
        totalDuration = decodedDuration?.isFinite == true ? max(1, decodedDuration ?? 1) : nil
        let decodedPaused = try container.decodeIfPresent(TimeInterval.self, forKey: .pausedRemaining)
        pausedRemaining = decodedPaused?.isFinite == true ? max(0, decodedPaused ?? 0) : nil
    }
}

enum SharedPomodoroPhase: String, Codable {
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

struct SharedPomodoroState: Codable {
    let taskTitle: String
    let phase: SharedPomodoroPhase
    let focusMinutes: Int
    let shortBreakMinutes: Int
    let longBreakMinutes: Int
    let roundsBeforeLongBreak: Int
    let weeklyFocusGoalMinutes: Int
    let completedFocusSessions: Int
    let isRunning: Bool
    let endDate: Date?
    let pausedRemaining: TimeInterval
    let sessionStartedAt: Date?
    let activeStartedAt: Date?
    let accumulatedElapsed: TimeInterval
    let stopwatchRunning: Bool
    let stopwatchSessionStartedAt: Date?
    let stopwatchActiveStartedAt: Date?
    let stopwatchAccumulated: TimeInterval

    enum CodingKeys: String, CodingKey {
        case taskTitle, phase, focusMinutes, shortBreakMinutes, longBreakMinutes
        case roundsBeforeLongBreak, weeklyFocusGoalMinutes, completedFocusSessions, isRunning, endDate
        case pausedRemaining, sessionStartedAt, activeStartedAt, accumulatedElapsed
        case stopwatchRunning, stopwatchSessionStartedAt
        case stopwatchActiveStartedAt, stopwatchAccumulated
    }

    init(
        taskTitle: String,
        phase: SharedPomodoroPhase,
        focusMinutes: Int,
        shortBreakMinutes: Int,
        longBreakMinutes: Int,
        roundsBeforeLongBreak: Int,
        completedFocusSessions: Int,
        isRunning: Bool,
        endDate: Date?,
        pausedRemaining: TimeInterval,
        weeklyFocusGoalMinutes: Int = 10 * 60,
        sessionStartedAt: Date? = nil,
        activeStartedAt: Date? = nil,
        accumulatedElapsed: TimeInterval = 0,
        stopwatchRunning: Bool = false,
        stopwatchSessionStartedAt: Date? = nil,
        stopwatchActiveStartedAt: Date? = nil,
        stopwatchAccumulated: TimeInterval = 0
    ) {
        self.taskTitle = taskTitle
        self.phase = phase
        self.focusMinutes = focusMinutes
        self.shortBreakMinutes = shortBreakMinutes
        self.longBreakMinutes = longBreakMinutes
        self.roundsBeforeLongBreak = roundsBeforeLongBreak
        self.weeklyFocusGoalMinutes = weeklyFocusGoalMinutes
        self.completedFocusSessions = completedFocusSessions
        self.isRunning = isRunning
        self.endDate = endDate
        self.pausedRemaining = pausedRemaining
        self.sessionStartedAt = sessionStartedAt
        self.activeStartedAt = activeStartedAt
        self.accumulatedElapsed = accumulatedElapsed
        self.stopwatchRunning = stopwatchRunning
        self.stopwatchSessionStartedAt = stopwatchSessionStartedAt
        self.stopwatchActiveStartedAt = stopwatchActiveStartedAt
        self.stopwatchAccumulated = stopwatchAccumulated
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawTitle = try container.decodeIfPresent(String.self, forKey: .taskTitle) ?? "专注当前任务"
        let trimmedTitle = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        taskTitle = String((trimmedTitle.isEmpty ? "专注当前任务" : trimmedTitle).prefix(40))
        let decodedPhase = try container.decodeIfPresent(SharedPomodoroPhase.self, forKey: .phase) ?? .focus
        phase = decodedPhase
        let decodedFocus = min(120, max(1, try container.decodeIfPresent(Int.self, forKey: .focusMinutes) ?? 25))
        let decodedShortBreak = min(30, max(1, try container.decodeIfPresent(Int.self, forKey: .shortBreakMinutes) ?? 5))
        let decodedLongBreak = min(60, max(1, try container.decodeIfPresent(Int.self, forKey: .longBreakMinutes) ?? 15))
        focusMinutes = decodedFocus
        shortBreakMinutes = decodedShortBreak
        longBreakMinutes = decodedLongBreak
        roundsBeforeLongBreak = min(
            8,
            max(2, try container.decodeIfPresent(Int.self, forKey: .roundsBeforeLongBreak) ?? 4)
        )
        weeklyFocusGoalMinutes = min(
            168 * 60,
            max(60, try container.decodeIfPresent(Int.self, forKey: .weeklyFocusGoalMinutes) ?? 10 * 60)
        )
        completedFocusSessions = max(
            0,
            try container.decodeIfPresent(Int.self, forKey: .completedFocusSessions) ?? 0
        )

        let decodedEndDate = try container.decodeIfPresent(Date.self, forKey: .endDate)
        let requestedRunning = try container.decodeIfPresent(Bool.self, forKey: .isRunning) ?? false
        isRunning = requestedRunning && decodedEndDate != nil
        endDate = isRunning ? decodedEndDate : nil
        let phaseDuration: TimeInterval
        switch decodedPhase {
        case .focus: phaseDuration = TimeInterval(decodedFocus * 60)
        case .shortBreak: phaseDuration = TimeInterval(decodedShortBreak * 60)
        case .longBreak: phaseDuration = TimeInterval(decodedLongBreak * 60)
        }
        let decodedPaused = try container.decodeIfPresent(TimeInterval.self, forKey: .pausedRemaining)
            ?? phaseDuration
        pausedRemaining = min(
            phaseDuration,
            max(0, decodedPaused.isFinite ? decodedPaused : phaseDuration)
        )
        sessionStartedAt = try container.decodeIfPresent(Date.self, forKey: .sessionStartedAt)
        activeStartedAt = isRunning
            ? try container.decodeIfPresent(Date.self, forKey: .activeStartedAt)
            : nil
        let decodedAccumulated = try container.decodeIfPresent(TimeInterval.self, forKey: .accumulatedElapsed) ?? 0
        accumulatedElapsed = min(
            phaseDuration,
            max(0, decodedAccumulated.isFinite ? decodedAccumulated : 0)
        )

        let decodedStopwatchStart = try container.decodeIfPresent(Date.self, forKey: .stopwatchActiveStartedAt)
        let requestedStopwatchRunning = try container.decodeIfPresent(Bool.self, forKey: .stopwatchRunning) ?? false
        stopwatchRunning = requestedStopwatchRunning && decodedStopwatchStart != nil && !isRunning
        stopwatchSessionStartedAt = isRunning
            ? nil
            : try container.decodeIfPresent(Date.self, forKey: .stopwatchSessionStartedAt)
        stopwatchActiveStartedAt = stopwatchRunning ? decodedStopwatchStart : nil
        let decodedStopwatch = try container.decodeIfPresent(TimeInterval.self, forKey: .stopwatchAccumulated) ?? 0
        stopwatchAccumulated = isRunning
            ? 0
            : max(0, decodedStopwatch.isFinite ? decodedStopwatch : 0)
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

    func duration(for phase: SharedPomodoroPhase) -> TimeInterval {
        switch phase {
        case .focus: return TimeInterval(focusMinutes * 60)
        case .shortBreak: return TimeInterval(shortBreakMinutes * 60)
        case .longBreak: return TimeInterval(longBreakMinutes * 60)
        }
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

    func remaining(at date: Date) -> TimeInterval {
        guard isRunning, let endDate else { return max(0, pausedRemaining) }
        return max(0, endDate.timeIntervalSince(date))
    }
}

struct SharedPomodoroSessionRecord: Codable {
    let phase: SharedPomodoroPhase
    let actualDuration: TimeInterval
    let startedAt: Date
    let endedAt: Date

    enum CodingKeys: String, CodingKey {
        case phase, actualDuration, startedAt, endedAt
    }
}

struct CountdownEntry: TimelineEntry {
    let date: Date
    let displayMode: String
    let timeUnit: String
    let item: SharedCountdownItem?
    let pomodoro: SharedPomodoroState?
    let pomodoroHistory: [SharedPomodoroSessionRecord]
}

enum CountdownWidgetDisplayMode: String, AppEnum {
    case followApp
    case pomodoro
    case countdown
    case stopwatch
    case weekly
    case both

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "显示内容")
    }

    static var caseDisplayRepresentations: [CountdownWidgetDisplayMode: DisplayRepresentation] {
        [
            .followApp: DisplayRepresentation(title: "跟随时隙"),
            .pomodoro: DisplayRepresentation(title: "番茄钟"),
            .countdown: DisplayRepresentation(title: "倒计时"),
            .stopwatch: DisplayRepresentation(title: "正计时"),
            .weekly: DisplayRepresentation(title: "本周专注目标"),
            .both: DisplayRepresentation(title: "番茄钟 + 倒计时")
        ]
    }
}

/// 可配置小组件使用的倒计时目标。
///
/// 目标只保存稳定的 UUID，标题与日期在小组件配置界面打开时从共享状态重新读取，
/// 这样编辑倒计时名称或目标时间后，不会留下过期的配置副本。
struct CountdownWidgetTarget: AppEntity, Hashable, Sendable {
    let id: String
    let title: String
    let targetDate: Date

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "倒计时目标")
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }

    static let defaultQuery = CountdownWidgetTargetQuery()

    init(item: SharedCountdownItem) {
        id = item.id.uuidString
        title = item.title
        targetDate = item.targetDate
    }
}

struct CountdownWidgetTargetQuery: EntityQuery {
    func entities(for identifiers: [CountdownWidgetTarget.ID]) async throws -> [CountdownWidgetTarget] {
        let targets = CountdownEntryFactory.loadCountdownItems().map(CountdownWidgetTarget.init(item:))
        let targetsByID = Dictionary(uniqueKeysWithValues: targets.map { ($0.id, $0) })
        return identifiers.compactMap { targetsByID[$0] }
    }

    func suggestedEntities() async throws -> [CountdownWidgetTarget] {
        let items = CountdownEntryFactory.loadCountdownItems()
        let orderedItems = items.sorted { left, right in
            if left.isPinned != right.isPinned {
                return left.isPinned && !right.isPinned
            }
            return (left.createdAt ?? left.targetDate) < (right.createdAt ?? right.targetDate)
        }
        return orderedItems.map(CountdownWidgetTarget.init(item:))
    }

    func defaultResult() async -> CountdownWidgetTarget? {
        guard let item = CountdownEntryFactory.loadCountdownItems().first(where: \.isPinned)
                ?? CountdownEntryFactory.loadCountdownItems().first else {
            return nil
        }
        return CountdownWidgetTarget(item: item)
    }
}

struct CountdownWidgetConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "时隙桌面小组件"
    static let description = IntentDescription("为每个小组件分别选择显示内容和倒计时目标。")

    @Parameter(title: "显示内容")
    var displayMode: CountdownWidgetDisplayMode?

    @Parameter(title: "倒计时目标")
    var countdownTarget: CountdownWidgetTarget?

    init() {
        displayMode = .followApp
        countdownTarget = nil
    }
}

enum CountdownEntryFactory {
    static func placeholder(displayMode: String = "both") -> CountdownEntry {
        CountdownEntry(
            date: Date(),
            displayMode: displayMode,
            timeUnit: "days",
            item: nil,
            pomodoro: SharedPomodoroState(
                taskTitle: "完成今天最重要的任务",
                phase: .focus,
                focusMinutes: 25,
                shortBreakMinutes: 5,
                longBreakMinutes: 15,
                roundsBeforeLongBreak: 4,
                completedFocusSessions: 1,
                isRunning: true,
                endDate: Date().addingTimeInterval(1500),
                pausedRemaining: 1500
            ),
            pomodoroHistory: []
        )
    }

    struct Snapshot {
        let displayMode: String
        let timeUnit: String
        let item: SharedCountdownItem?
        let pomodoro: SharedPomodoroState?
        let pomodoroHistory: [SharedPomodoroSessionRecord]
    }

    struct WidgetStateFile: Codable {
        let items: [SharedCountdownItem]?
        let pomodoro: SharedPomodoroState?
        let pomodoroHistory: [SharedPomodoroSessionRecord]?
        let displayMode: String?
        let timeUnit: String?
        let updatedAt: Date?
    }

    static var sharedPreferencesURL: URL? {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: sharedDefaultsName
        ) else { return nil }
        return container
            .appendingPathComponent("Library/Preferences", isDirectory: true)
            .appendingPathComponent("\(sharedDefaultsName).plist")
    }

    static func sharedPreferencesDictionary() -> [String: Any]? {
        guard let url = sharedPreferencesURL,
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dict = plist as? [String: Any] else {
            return nil
        }
        return dict
    }

    /// 主 App 每次状态变化都会原子写入这份 JSON，扩展进程直接读它，
    /// 不经过 cfprefsd / UserDefaults 缓存，因此状态变化会立即被小组件看到。
    static var sharedStateFileURL: URL? {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: sharedDefaultsName
        ) else { return nil }
        return container
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent("widget-state.json")
    }

    static func loadWidgetStateFile() -> WidgetStateFile? {
        guard let url = sharedStateFileURL,
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetStateFile.self, from: data)
    }

    static func loadSharedData(forKey key: String) -> Data? {
        if let dict = sharedPreferencesDictionary(), let value = dict[key] as? Data {
            return value
        }
        return UserDefaults(suiteName: sharedDefaultsName)?.data(forKey: key)
    }

    static func loadSharedString(forKey key: String) -> String? {
        if let dict = sharedPreferencesDictionary(), let value = dict[key] as? String {
            return value
        }
        return UserDefaults(suiteName: sharedDefaultsName)?.string(forKey: key)
    }

    static func loadCountdownItems() -> [SharedCountdownItem] {
        if let items = loadWidgetStateFile()?.items {
            return items
        }
        guard let data = loadSharedData(forKey: sharedItemsKey) else { return [] }
        return (try? JSONDecoder().decode([SharedCountdownItem].self, from: data)) ?? []
    }

    static func loadSnapshot(
        displayModeOverride: String?,
        countdownTargetIDOverride: String? = nil
    ) -> Snapshot {
        let stateFile = loadWidgetStateFile()

        let requestedDisplayMode = displayModeOverride
            ?? stateFile?.displayMode
            ?? loadSharedString(forKey: widgetDisplayModeKey)
            ?? "both"
        let displayMode = ["countdown", "pomodoro", "stopwatch", "weekly", "both"]
            .contains(requestedDisplayMode) ? requestedDisplayMode : "both"
        let requestedTimeUnit = stateFile?.timeUnit
            ?? loadSharedString(forKey: "widgetTimeUnit")
            ?? "days"
        let timeUnit = ["days", "hours", "precise", "auto"].contains(requestedTimeUnit)
            ? requestedTimeUnit : "auto"

        let items = loadCountdownItems()
        let requestedTarget = countdownTargetIDOverride.flatMap { requestedID in
            items.first { $0.id.uuidString.caseInsensitiveCompare(requestedID) == .orderedSame }
        }
        let item = requestedTarget ?? items.first(where: \.isPinned) ?? items.first

        var pomodoro: SharedPomodoroState?
        if let state = stateFile?.pomodoro {
            pomodoro = state
        } else if let data = loadSharedData(forKey: sharedPomodoroKey) {
            pomodoro = try? JSONDecoder().decode(SharedPomodoroState.self, from: data)
        }

        let pomodoroHistory: [SharedPomodoroSessionRecord]
        if let history = stateFile?.pomodoroHistory {
            pomodoroHistory = history
        } else if let data = loadSharedData(forKey: sharedPomodoroHistoryKey),
                  let history = try? JSONDecoder().decode([SharedPomodoroSessionRecord].self, from: data) {
            pomodoroHistory = history
        } else {
            pomodoroHistory = []
        }
        return Snapshot(
            displayMode: displayMode,
            timeUnit: timeUnit,
            item: item,
            pomodoro: pomodoro,
            pomodoroHistory: pomodoroHistory
        )
    }

    static func makeEntry(
        at date: Date,
        displayModeOverride: String? = nil,
        countdownTargetIDOverride: String? = nil
    ) -> CountdownEntry {
        let snapshot = loadSnapshot(
            displayModeOverride: displayModeOverride,
            countdownTargetIDOverride: countdownTargetIDOverride
        )
        return CountdownEntry(
            date: date,
            displayMode: snapshot.displayMode,
            timeUnit: snapshot.timeUnit,
            item: snapshot.item,
            pomodoro: snapshot.pomodoro,
            pomodoroHistory: snapshot.pomodoroHistory
        )
    }

    static func makeTimeline(
        displayModeOverride: String? = nil,
        countdownTargetIDOverride: String? = nil
    ) -> Timeline<CountdownEntry> {
        let now = Date()
        let snapshot = loadSnapshot(
            displayModeOverride: displayModeOverride,
            countdownTargetIDOverride: countdownTargetIDOverride
        )
        let hasActivePomodoro = snapshot.pomodoro?.isRunning == true
            && (snapshot.pomodoro?.endDate ?? .distantPast) > now
        let hasActiveTimer = hasActivePomodoro || snapshot.pomodoro?.stopwatchRunning == true
        let fallbackInterval: TimeInterval = hasActiveTimer ? 15 * 60 : 60 * 60
        let fallbackDate = now.addingTimeInterval(fallbackInterval)

        // 数字走秒交给 Text(..., style: .timer)，时间线只负责跨越“阶段结束/目标到达”
        // 这类语义边界。应用内状态变化仍会主动 reloadTimelines；这里用 15/60 分钟
        // 做低频兜底，避免高频刷新耗尽 WidgetKit 预算后反而长期不更新。
        var dates = [now]
        if let endDate = snapshot.pomodoro?.endDate,
           endDate > now,
           endDate <= fallbackDate {
            dates.append(endDate.addingTimeInterval(0.5))
        }
        if let targetDate = snapshot.item?.targetDate,
           snapshot.item?.pausedRemaining == nil,
           targetDate > now,
           targetDate <= fallbackDate {
            dates.append(targetDate.addingTimeInterval(0.5))
        }
        dates.append(fallbackDate)

        let entries = Array(Set(dates.map { $0.timeIntervalSinceReferenceDate }))
            .sorted()
            .map { timestamp in
            CountdownEntry(
                date: Date(timeIntervalSinceReferenceDate: timestamp),
                displayMode: snapshot.displayMode,
                timeUnit: snapshot.timeUnit,
                item: snapshot.item,
                pomodoro: snapshot.pomodoro,
                pomodoroHistory: snapshot.pomodoroHistory
            )
        }
        return Timeline(entries: entries, policy: .after(fallbackDate))
    }
}

struct CountdownProvider: TimelineProvider {
    func placeholder(in context: Context) -> CountdownEntry {
        CountdownEntryFactory.placeholder()
    }

    func getSnapshot(in context: Context, completion: @escaping (CountdownEntry) -> Void) {
        completion(CountdownEntryFactory.makeEntry(at: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CountdownEntry>) -> Void) {
        completion(CountdownEntryFactory.makeTimeline())
    }
}

struct FixedDisplayModeProvider: TimelineProvider {
    let displayMode: String

    func placeholder(in context: Context) -> CountdownEntry {
        CountdownEntryFactory.placeholder(displayMode: displayMode)
    }

    func getSnapshot(in context: Context, completion: @escaping (CountdownEntry) -> Void) {
        completion(CountdownEntryFactory.makeEntry(at: Date(), displayModeOverride: displayMode))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CountdownEntry>) -> Void) {
        completion(CountdownEntryFactory.makeTimeline(displayModeOverride: displayMode))
    }
}

struct ConfigurableCountdownProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> CountdownEntry {
        CountdownEntryFactory.placeholder()
    }

    func snapshot(for configuration: CountdownWidgetConfiguration, in context: Context) async -> CountdownEntry {
        CountdownEntryFactory.makeEntry(
            at: Date(),
            displayModeOverride: displayMode(for: configuration),
            countdownTargetIDOverride: countdownTargetID(for: configuration)
        )
    }

    func timeline(for configuration: CountdownWidgetConfiguration, in context: Context) async -> Timeline<CountdownEntry> {
        CountdownEntryFactory.makeTimeline(
            displayModeOverride: displayMode(for: configuration),
            countdownTargetIDOverride: countdownTargetID(for: configuration)
        )
    }

    private func displayMode(for configuration: CountdownWidgetConfiguration) -> String? {
        switch configuration.displayMode ?? .followApp {
        case .followApp: return nil
        case .pomodoro: return "pomodoro"
        case .countdown: return "countdown"
        case .stopwatch: return "stopwatch"
        case .weekly: return "weekly"
        case .both: return "both"
        }
    }

    private func countdownTargetID(for configuration: CountdownWidgetConfiguration) -> String? {
        configuration.countdownTarget?.id
    }
}

struct CountdownDesktopWidgetView: View {
    let entry: CountdownEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme

    /// 点击小组件时打开对应的应用页面。
    private var widgetOpenURL: URL? {
        switch entry.displayMode {
        case "countdown":
            return URL(string: "timeslot://countdown")
        case "pomodoro":
            return URL(string: "timeslot://pomodoro")
        case "stopwatch":
            return URL(string: "timeslot://pomodoro")
        case "weekly":
            return URL(string: "timeslot://pomodoro")
        default:
            return URL(string: "timeslot://widget")
        }
    }

    var body: some View {
        content(at: entry.date)
        .environment(\.calendar, beijingCalendar)
        .environment(\.timeZone, beijingTimeZone)
        .environment(\.locale, beijingLocale)
        .widgetURL(widgetOpenURL)
        // 小组件的标签与标题沿用系统字形；计时读数在各自的数字样式中保留圆体。
        .fontDesign(.default)
    }

    @ViewBuilder
    private func content(at date: Date) -> some View {
        let snap = CountdownEntryFactory.Snapshot(
            displayMode: entry.displayMode,
            timeUnit: entry.timeUnit,
            item: entry.item,
            pomodoro: entry.pomodoro,
            pomodoroHistory: entry.pomodoroHistory
        )
        let mode = entry.displayMode
        Group {
            if mode == "both", snap.pomodoro != nil || snap.item != nil {
                combinedContent(snap.pomodoro, snap.item, date: date)
            } else if mode == "weekly" {
                weeklyFocusContent(state: snap.pomodoro, history: snap.pomodoroHistory, date: date)
            } else if mode == "stopwatch" {
                if let pomodoro = snap.pomodoro, pomodoro.isStopwatchActive {
                    stopwatchContent(pomodoro, date: date)
                } else {
                    modeEmptyState(
                        icon: "stopwatch.fill",
                        title: "正计时未开始",
                        subtitle: "开始正计时后，这里会显示实时用时。"
                    )
                }
            } else if mode == "pomodoro" {
                if let pomodoro = snap.pomodoro, !pomodoro.isStopwatchActive {
                    countdownPomodoroContent(pomodoro, date: date)
                } else {
                    modeEmptyState(
                        icon: "timer",
                        title: "番茄钟未开始",
                        subtitle: "切换到番茄钟并开始专注。"
                    )
                }
            } else if let item = snap.item {
                countdownContent(item, date: date)
            } else {
                emptyState
            }
        }
        .containerBackground(for: .widget) {
            WidgetBackdrop(accent: accentFor(snap), family: family)
        }
    }

    private func accentFor(_ snap: CountdownEntryFactory.Snapshot) -> Color {
        if entry.displayMode == "stopwatch" || entry.displayMode == "weekly" {
            return adaptiveAccent(widgetAccentLightHex)
        }
        if (entry.displayMode == "pomodoro" || entry.displayMode == "both"), let pomodoro = snap.pomodoro {
            return adaptiveAccent(graphiteHex(for: pomodoro.phase))
        }
        if snap.item != nil {
            return adaptiveAccent(widgetAccentLightHex)
        }
        return adaptiveAccent(widgetAccentLightHex)
    }

    /// 保存数据使用稳定的 sRGB 色值；渲染时只在深色桌面上轻微提亮，
    /// 避免青绿、靛蓝等颜色在深色墙纸上失去对比度。
    /// 番茄钟阶段色跟随石墨灰主题：专注/短休/长休同族灰档。
    private func graphiteHex(for phase: SharedPomodoroPhase) -> String {
        switch phase {
        case .focus: return widgetAccentLightHex
        case .shortBreak: return widgetBreakLightHex
        case .longBreak: return widgetLongBreakLightHex
        }
    }

    private func adaptiveAccent(_ hex: String) -> Color {
        let components = WidgetColorHex.components(from: hex)
            ?? WidgetColorHex.components(from: WidgetColorHex.fallback)
            ?? (0.17, 0.55, 0.49, 1)
        guard colorScheme == .dark else {
            return Color(
                .sRGB,
                red: components.red,
                green: components.green,
                blue: components.blue,
                opacity: components.alpha
            )
        }
        let lift = 0.18
        return Color(
            .sRGB,
            red: components.red + (1 - components.red) * lift,
            green: components.green + (1 - components.green) * lift,
            blue: components.blue + (1 - components.blue) * lift,
            opacity: components.alpha
        )
    }

    private func countdownContent(_ item: SharedCountdownItem, date: Date) -> some View {
        let remaining = item.remaining(at: date)
        let accent = adaptiveAccent(widgetAccentLightHex)

        return VStack(alignment: .leading, spacing: family == .systemSmall ? 8 : 12) {
            HStack {
                WidgetModeLabel(title: "倒计时")
                Spacer()
                Circle()
                    .fill(accent)
                    .frame(width: 8, height: 8)
                    .widgetAccentable()
            }

            Text(item.title)
                .font(.headline.weight(.semibold))
                .fontDesign(.default)
                .tracking(0.2)
                .lineLimit(family == .systemSmall ? 2 : 1)

            Spacer(minLength: 0)

            if remaining > 0 {
                countdownValue(
                    item,
                    remaining: remaining,
                    fontSize: family == .systemSmall ? 23 : 31,
                    minimumScaleFactor: 0.72
                )
            }

            if let span = item.totalDuration, span > 0 {
                WidgetProgressBar(
                    value: remaining <= 0 ? 1 : min(1, max(0, 1 - remaining / span)),
                    color: accent,
                    height: family == .systemSmall ? 5 : 6
                )
            }

            if item.pausedRemaining != nil, remaining > 0 {
                Label("已暂停", systemImage: "pause.fill")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            } else if remaining > 0 {
                Text(item.targetDate, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if remaining <= 0 {
                Label("时间到", systemImage: "checkmark.circle.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(accent)
            }
        }
        .padding(family == .systemSmall ? 14 : 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func stopwatchContent(_ state: SharedPomodoroState, date: Date) -> some View {
        let accent = adaptiveAccent(widgetAccentLightHex)
        let elapsed = state.stopwatchElapsed(at: date)

        return VStack(alignment: .leading, spacing: family == .systemSmall ? 8 : 10) {
            HStack {
                WidgetModeLabel(title: "正计时")
                Spacer()
                Circle()
                    .fill(state.stopwatchRunning ? accent : Color.secondary.opacity(0.4))
                    .frame(width: 8, height: 8)
                    .widgetAccentable()
            }

            Text(state.taskTitle.isEmpty ? "专注" : state.taskTitle)
                .font(.headline.weight(.semibold))
                .fontDesign(.default)
                .tracking(0.2)
                .lineLimit(family == .systemSmall ? 2 : 1)

            Spacer(minLength: 0)

            if state.stopwatchRunning,
               let activeStartedAt = state.stopwatchActiveStartedAt {
                Text(activeStartedAt.addingTimeInterval(-state.stopwatchAccumulated), style: .timer)
                    .font(.system(size: family == .systemSmall ? 28 : 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .tracking(0.3)
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .widgetAccentable()
            } else {
                Text(formatStopwatch(elapsed))
                    .font(.system(size: family == .systemSmall ? 28 : 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .tracking(0.3)
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .widgetAccentable()
            }

            WidgetProgressBar(
                value: CGFloat((elapsed.truncatingRemainder(dividingBy: 60)) / 60),
                color: accent,
                height: family == .systemSmall ? 5 : 6
            )

            HStack {
                Text(state.stopwatchRunning ? "进行中" : (state.isStopwatchActive ? "已暂停" : "未开始"))
                    .font(.caption2.weight(.medium))
                    .tracking(0.4)
                    .foregroundStyle(accent)
                Spacer()
                Text("正计时")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(family == .systemSmall ? 14 : 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func countdownPomodoroContent(_ state: SharedPomodoroState, date: Date) -> some View {
        let remaining = state.remaining(at: date)
        let accent = adaptiveAccent(graphiteHex(for: state.phase))
        let phaseDuration = max(1, state.duration(for: state.phase))
        let phaseProgress = min(1, max(0, state.elapsed(at: date) / phaseDuration))

        return VStack(alignment: .leading, spacing: family == .systemSmall ? 8 : 10) {
            HStack {
                WidgetModeLabel(title: "番茄钟")
                Spacer()
                Circle()
                    .fill(state.isRunning ? accent : Color.secondary.opacity(0.4))
                    .frame(width: 8, height: 8)
                    .widgetAccentable()
            }

            Text(state.taskTitle.isEmpty ? state.phase.title : state.taskTitle)
                .font(.headline.weight(.semibold))
                .fontDesign(.default)
                .tracking(0.2)
                .lineLimit(family == .systemSmall ? 2 : 1)

            Spacer(minLength: 0)

            if state.isRunning, let endDate = state.endDate, remaining > 0 {
                Text(endDate, style: .timer)
                    .font(.system(size: family == .systemSmall ? 28 : 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .tracking(0.3)
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .widgetAccentable()
            } else if state.isRunning, remaining <= 0 {
                Text("阶段结束")
                    .font(.system(size: family == .systemSmall ? 24 : 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .widgetAccentable()
            } else {
                Text(formatPomodoro(remaining))
                    .font(.system(size: family == .systemSmall ? 28 : 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .tracking(0.3)
                    .foregroundStyle(accent)
                    .widgetAccentable()
            }

            WidgetProgressBar(
                value: phaseProgress,
                color: accent,
                height: family == .systemSmall ? 5 : 6
            )

            HStack {
                Text(state.isRunning && remaining <= 0 ? "打开时隙继续" : state.phase.title)
                    .font(.caption2.weight(.medium))
                    .tracking(0.4)
                    .foregroundStyle(accent)
                Spacer()
                Text("完成 \(state.completedFocusSessions) 轮")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(family == .systemSmall ? 14 : 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func weeklyFocusContent(
        state: SharedPomodoroState?,
        history: [SharedPomodoroSessionRecord],
        date: Date
    ) -> some View {
        let goalMinutes = max(1, state?.weeklyFocusGoalMinutes ?? 10 * 60)
        let completedMinutes = weeklyFocusDuration(state: state, history: history, at: date) / 60
        let progress = min(1, max(0, completedMinutes / Double(goalMinutes)))
        let accent = adaptiveAccent(widgetAccentLightHex)

        VStack(alignment: .leading, spacing: family == .systemSmall ? 8 : 12) {
            HStack(spacing: 6) {
                WidgetModeLabel(title: "本周专注")
                Spacer()
                Text("周一至周日")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(verbatim: formatWeeklyFocus(completedMinutes))
                .font(.system(size: family == .systemSmall ? 28 : 36, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .tracking(0.2)
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .widgetAccentable()

            WidgetProgressBar(
                value: progress,
                color: accent,
                height: family == .systemSmall ? 7 : 8
            )

            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: "目标 \(formatWeeklyFocus(Double(goalMinutes)))")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(verbatim: "完成 \(Int((progress * 100).rounded()))%")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(accent)
            }

            if family != .systemSmall {
                Text("专注阶段与正计时都会计入本周累计")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(family == .systemSmall ? 14 : 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func modeEmptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(adaptiveAccent(widgetAccentLightHex))
                .widgetAccentable()
            Text(title)
                .font(.headline.weight(.semibold))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(family == .systemSmall ? 14 : 16)
    }

    private func weeklyFocusDuration(
        state: SharedPomodoroState?,
        history: [SharedPomodoroSessionRecord],
        at date: Date
    ) -> TimeInterval {
        let bounds = weeklyBounds(at: date)
        var total = history.reduce(0) { partial, record in
            guard record.phase == .focus else { return partial }
            return partial + overlapDuration(record, bounds: bounds)
        }

        guard let state else { return total }
        if state.isStopwatchActive {
            let elapsed = state.stopwatchElapsed(at: date)
            total += currentSessionDuration(
                elapsed: elapsed,
                startedAt: state.stopwatchSessionStartedAt,
                bounds: bounds,
                date: date
            )
        } else if state.phase == .focus, state.sessionStartedAt != nil {
            let elapsed = state.isRunning ? state.elapsed(at: date) : state.accumulatedElapsed
            total += currentSessionDuration(
                elapsed: elapsed,
                startedAt: state.sessionStartedAt,
                bounds: bounds,
                date: date
            )
        }
        return max(0, total)
    }

    private func weeklyBounds(at date: Date) -> (start: Date, end: Date) {
        let day = beijingCalendar.startOfDay(for: date)
        let weekday = beijingCalendar.component(.weekday, from: day)
        let daysFromMonday = (weekday + 5) % 7
        let start = beijingCalendar.date(byAdding: .day, value: -daysFromMonday, to: day) ?? day
        let end = beijingCalendar.date(byAdding: .day, value: 7, to: start) ?? start.addingTimeInterval(7 * 86400)
        return (start, end)
    }

    private func overlapDuration(
        _ record: SharedPomodoroSessionRecord,
        bounds: (start: Date, end: Date)
    ) -> TimeInterval {
        let start = max(record.startedAt, bounds.start)
        let end = min(record.endedAt, bounds.end)
        let overlap = end.timeIntervalSince(start)
        guard overlap > 0 else { return 0 }
        let wallDuration = record.endedAt.timeIntervalSince(record.startedAt)
        guard wallDuration > 0 else { return record.actualDuration }
        return record.actualDuration * min(1, overlap / wallDuration)
    }

    private func currentSessionDuration(
        elapsed: TimeInterval,
        startedAt: Date?,
        bounds: (start: Date, end: Date),
        date: Date
    ) -> TimeInterval {
        guard elapsed > 0 else { return 0 }
        let sessionStart = startedAt ?? date.addingTimeInterval(-elapsed)
        let wallElapsedInWeek = max(0, date.timeIntervalSince(max(sessionStart, bounds.start)))
        return min(elapsed, wallElapsedInWeek)
    }

    private func formatWeeklyFocus(_ minutes: Double) -> String {
        let totalMinutes = max(0, Int(minutes.rounded(.down)))
        let hours = totalMinutes / 60
        let remainder = totalMinutes % 60
        if hours > 0, remainder > 0 { return "\(hours)小时 \(remainder)分" }
        if hours > 0 { return "\(hours)小时" }
        return "\(remainder)分"
    }

    // MARK: - 同时显示番茄钟与倒计时

    private func combinedContent(
        _ pomodoro: SharedPomodoroState?,
        _ item: SharedCountdownItem?,
        date: Date
    ) -> some View {
        let compact = family == .systemSmall
        return Group {
            if family == .systemMedium {
                HStack(alignment: .top, spacing: 14) {
                    pomodoroPane(pomodoro, compact: true, date: date)
                        .frame(maxHeight: .infinity, alignment: .top)
                    Divider()
                    countdownPane(item, compact: true, date: date)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            } else if family == .systemLarge {
                VStack(alignment: .leading, spacing: 14) {
                    pomodoroPane(pomodoro, compact: false, date: date)
                        .frame(maxHeight: .infinity, alignment: .top)
                    Divider()
                    countdownPane(item, compact: false, date: date)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    pomodoroPane(pomodoro, compact: compact, date: date)
                    Divider()
                    countdownPane(item, compact: compact, date: date)
                }
            }
        }
        .padding(compact ? 12 : 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func pomodoroPane(_ state: SharedPomodoroState?, compact: Bool, date: Date) -> some View {
        if let state {
            if state.isStopwatchActive {
                stopwatchPane(state, compact: compact, date: date)
            } else {
                countdownPomodoroPane(state, compact: compact, date: date)
            }
        } else {
            combinedPlaceholder(icon: "timer", text: "没有番茄钟")
        }
    }

    @ViewBuilder
    private func stopwatchPane(_ state: SharedPomodoroState, compact: Bool, date: Date) -> some View {
        let accent = adaptiveAccent(widgetAccentLightHex)
        let elapsed = state.stopwatchElapsed(at: date)

        VStack(alignment: .leading, spacing: compact ? 3 : 6) {
            HStack(spacing: 4) {
                Image(systemName: "stopwatch.fill")
                    .font(.system(size: 9, weight: .semibold))
                Text("正计时")
                    .font(.caption2.weight(.medium))
                    .tracking(0.4)
                Spacer(minLength: 0)
                Circle()
                    .fill(state.stopwatchRunning ? accent : Color.secondary.opacity(0.4))
                    .frame(width: 6, height: 6)
                    .widgetAccentable()
            }
            .foregroundStyle(.secondary)

            Text(state.taskTitle.isEmpty ? "专注" : state.taskTitle)
                .font(.system(size: compact ? 11 : 13, weight: .semibold))
                .lineLimit(1)

            Group {
                if state.stopwatchRunning,
                   let activeStartedAt = state.stopwatchActiveStartedAt {
                    Text(activeStartedAt.addingTimeInterval(-state.stopwatchAccumulated), style: .timer)
                } else {
                    Text(formatStopwatch(elapsed))
                }
            }
            .font(.system(size: compact ? 22 : 30, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .tracking(0.3)
            .foregroundStyle(accent)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .widgetAccentable()

            if !compact {
                WidgetProgressBar(
                    value: CGFloat((elapsed.truncatingRemainder(dividingBy: 60)) / 60),
                    color: accent,
                    height: 4
                )
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func countdownPomodoroPane(_ state: SharedPomodoroState, compact: Bool, date: Date) -> some View {
        let accent = adaptiveAccent(graphiteHex(for: state.phase))
        let remaining = state.remaining(at: date)
        let phaseDuration = max(1, state.duration(for: state.phase))
        let phaseProgress = min(1, max(0, state.elapsed(at: date) / phaseDuration))
        return VStack(alignment: .leading, spacing: compact ? 3 : 6) {
            HStack(spacing: 4) {
                Image(systemName: state.phase.icon)
                    .font(.system(size: 9, weight: .semibold))
                Text(state.phase.title)
                    .font(.caption2.weight(.medium))
                    .tracking(0.4)
                Spacer(minLength: 0)
                Circle()
                    .fill(state.isRunning ? accent : Color.secondary.opacity(0.4))
                    .frame(width: 6, height: 6)
                    .widgetAccentable()
            }
            .foregroundStyle(.secondary)

            Text(state.taskTitle.isEmpty ? state.phase.title : state.taskTitle)
                .font(.system(size: compact ? 11 : 13, weight: .semibold))
                .lineLimit(1)

            Group {
                if state.isRunning, let endDate = state.endDate, remaining > 0 {
                    Text(endDate, style: .timer)
                } else if state.isRunning, remaining <= 0 {
                    Text("阶段结束")
                } else {
                    Text(formatPomodoro(remaining))
                }
            }
            .font(.system(size: compact ? 22 : 30, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .tracking(0.3)
            .foregroundStyle(accent)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .widgetAccentable()

            if !compact {
                WidgetProgressBar(
                    value: phaseProgress,
                    color: accent,
                    height: 4
                )
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func countdownPane(_ item: SharedCountdownItem?, compact: Bool, date: Date) -> some View {
        if let item {
            let accent = adaptiveAccent(widgetAccentLightHex)
            let remaining = item.remaining(at: date)
            VStack(alignment: .leading, spacing: compact ? 3 : 6) {
                HStack(spacing: 4) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 9, weight: .semibold))
                    Text("倒计时")
                        .font(.caption2.weight(.medium))
                    .tracking(0.4)
                    Spacer(minLength: 0)
                    Circle()
                        .fill(item.pausedRemaining != nil ? Color.secondary.opacity(0.4) : accent)
                        .frame(width: 6, height: 6)
                        .widgetAccentable()
                }
                .foregroundStyle(.secondary)

                Text(item.title)
                    .font(.system(size: compact ? 11 : 13, weight: .semibold))
                    .lineLimit(1)

                if remaining > 0 {
                    countdownValue(
                        item,
                        remaining: remaining,
                        fontSize: compact ? 18 : 26,
                        minimumScaleFactor: 0.6
                    )
                } else {
                    Text("时间到")
                        .font(.system(size: compact ? 18 : 26, weight: .semibold, design: .rounded))
                        .foregroundStyle(accent)
                }

                if let span = item.totalDuration, span > 0, !compact {
                    WidgetProgressBar(
                        value: remaining <= 0 ? 1 : min(1, max(0, 1 - remaining / span)),
                        color: accent,
                        height: 4
                    )
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            combinedPlaceholder(icon: "calendar", text: "没有倒计时")
        }
    }

    private func combinedPlaceholder(icon: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
            Text(text)
                .font(.caption2)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "timer")
                .font(.title2)
                .foregroundStyle(adaptiveAccent(widgetAccentLightHex))
                .widgetAccentable()
            Text("还没有计时内容")
                .font(.headline.weight(.semibold))
                .fontDesign(.default)
                .tracking(0.2)
            Text("打开“时隙”创建倒计时或番茄钟。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(14)
    }

    @ViewBuilder
    private func countdownValue(
        _ item: SharedCountdownItem,
        remaining: TimeInterval,
        fontSize: CGFloat,
        minimumScaleFactor: CGFloat
    ) -> some View {
        // 自定义字符串由时间线驱动，只能按分钟变；最后一小时改用系统 timer，
        // 让“自动/精细”模式和番茄钟一样每秒连续更新。
        let usesLiveTimer = item.pausedRemaining == nil
            && remaining < 3600
            && (entry.timeUnit == "auto" || entry.timeUnit == "precise")

        Group {
            if usesLiveTimer {
                Text(item.targetDate, style: .timer)
            } else {
                Text(formatCountdown(remaining, unit: entry.timeUnit))
            }
        }
        .font(.system(size: fontSize, weight: .semibold, design: .rounded))
        .monospacedDigit()
        .tracking(0.3)
        .foregroundStyle(adaptiveAccent(widgetAccentLightHex))
        .lineLimit(1)
        .minimumScaleFactor(minimumScaleFactor)
        .widgetAccentable()
    }

    private func formatCountdown(_ remaining: TimeInterval, unit: String) -> String {
        let total = max(0, Int(ceil(remaining)))
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        switch unit {
        case "days":
            if days > 0 {
                return "\(days) 天"
            } else if hours > 0 {
                return "\(hours) 小时"
            } else if minutes > 0 {
                return "\(minutes) 分"
            } else {
                return "\(seconds) 秒"
            }
        case "hours":
            let totalHours = total / 3600
            if totalHours > 0 {
                return "\(totalHours) 小时"
            } else {
                return "\(minutes) 分"
            }
        case "precise":
            if days > 0 {
                return "\(days)天 \(hours)时 \(minutes)分"
            } else if hours > 0 {
                return "\(hours)小时 \(minutes)分"
            } else {
                return "\(minutes)分 \(seconds)秒"
            }
        default: // "auto"
            if days > 0 { return "\(days)天 \(hours)小时" }
            if hours > 0 { return "\(hours)小时 \(minutes)分" }
            if minutes > 0 { return "\(minutes)分" }
            return "\(seconds)秒"
        }
    }

    private func formatPomodoro(_ remaining: TimeInterval) -> String {
        let total = max(0, Int(ceil(remaining)))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private func formatStopwatch(_ elapsed: TimeInterval) -> String {
        let total = max(0, Int(elapsed))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

struct CountdownDesktopWidget: Widget {
    let kind = "CountdownDesktopWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CountdownProvider()) { entry in
            CountdownDesktopWidgetView(entry: entry)
        }
        .configurationDisplayName("时隙桌面小组件")
        .description("一眼查看倒计时和当前专注状态。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

struct ConfigurableCountdownDesktopWidget: Widget {
    let kind = "CountdownDesktopWidgetConfig"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: CountdownWidgetConfiguration.self,
            provider: ConfigurableCountdownProvider()
        ) { entry in
            CountdownDesktopWidgetView(entry: entry)
        }
        .configurationDisplayName("时隙 · 自定义")
        .description("选择倒计时、番茄钟、正计时或组合视图。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

struct CountdownOnlyWidget: Widget {
    let kind = "CountdownOnlyWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: FixedDisplayModeProvider(displayMode: "countdown")
        ) { entry in
            CountdownDesktopWidgetView(entry: entry)
        }
        .configurationDisplayName("时隙 · 倒计时")
        .description("持续关注一个重要目标。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

struct StopwatchOnlyWidget: Widget {
    let kind = "StopwatchOnlyWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: FixedDisplayModeProvider(displayMode: "stopwatch")
        ) { entry in
            CountdownDesktopWidgetView(entry: entry)
        }
        .configurationDisplayName("时隙 · 正计时")
        .description("实时查看当前任务的累计用时。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

struct PomodoroOnlyWidget: Widget {
    let kind = "PomodoroOnlyWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: FixedDisplayModeProvider(displayMode: "pomodoro")
        ) { entry in
            CountdownDesktopWidgetView(entry: entry)
        }
        .configurationDisplayName("时隙 · 番茄钟")
        .description("查看当前阶段、剩余时间和完成轮数。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

struct WeeklyFocusGoalWidget: Widget {
    let kind = "WeeklyFocusGoalWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: FixedDisplayModeProvider(displayMode: "weekly")
        ) { entry in
            CountdownDesktopWidgetView(entry: entry)
        }
        .configurationDisplayName("时隙 · 本周专注目标")
        .description("追踪本周专注时长和目标进度。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

@main
struct CountdownDesktopWidgetBundle: WidgetBundle {
    var body: some Widget {
        CountdownDesktopWidget()
        ConfigurableCountdownDesktopWidget()
        CountdownOnlyWidget()
        StopwatchOnlyWidget()
        PomodoroOnlyWidget()
        WeeklyFocusGoalWidget()
    }
}

extension Color {
    init(hex: String) {
        let value = WidgetColorHex.components(from: hex)
            ?? WidgetColorHex.components(from: WidgetColorHex.fallback)
            ?? (0.17, 0.55, 0.49, 1)
        self.init(
            .sRGB,
            red: value.red,
            green: value.green,
            blue: value.blue,
            opacity: value.alpha
        )
    }
}
