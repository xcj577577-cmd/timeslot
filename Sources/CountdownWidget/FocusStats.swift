import Foundation

/// 专注统计的唯一口径：北京时间、周一至周日、跨午夜/跨小时按墙钟比例切 `actualDuration`。
/// 只读，不写历史、不碰 App Group。进行中的会话由调用方单独传入，默认不计入已保存合计。
enum FocusStats {
    struct Slice: Equatable {
        var day: Date
        var hour: Int
        var taskTitle: String
        var duration: TimeInterval
    }

    struct WeekPace: Equatable {
        var savedSeconds: TimeInterval
        var goalSeconds: TimeInterval
        var remainingSeconds: TimeInterval
        var dailyTargetSeconds: TimeInterval
        var daysLeftIncludingToday: Int
        var headline: String
    }

    private struct DayTask: Hashable {
        var day: Date
        var taskTitle: String
    }

    static func isSavedFocus(_ record: PomodoroSessionRecord) -> Bool {
        record.actualDuration > 0 && (record.phase == .focus || record.status == .stopwatch)
    }

    /// 把一条记录裁进半开区间 [start, end)，暂停造成 actual < wall 时按比例分配。
    static func clippedDuration(
        _ record: PomodoroSessionRecord,
        within bounds: (start: Date, end: Date)?
    ) -> TimeInterval {
        guard let bounds else { return max(0, record.actualDuration) }
        let overlapStart = max(record.startedAt, bounds.start)
        let overlapEnd = min(record.endedAt, bounds.end)
        let overlap = max(0, overlapEnd.timeIntervalSince(overlapStart))
        let wall = record.endedAt.timeIntervalSince(record.startedAt)
        guard wall > 0 else { return overlap > 0 ? max(0, record.actualDuration) : 0 }
        return max(0, record.actualDuration * min(1, overlap / wall))
    }

    /// 按北京时间小时边界切开。`from`/`to` 为半开窗口，nil 表示记录自身起止。
    static func slices(
        _ record: PomodoroSessionRecord,
        from start: Date? = nil,
        to end: Date? = nil,
        calendar: Calendar = beijingCalendar
    ) -> [Slice] {
        guard isSavedFocus(record) else { return [] }
        let task = PomodoroTaskPalette.normalized(record.taskTitle)
        let rangeStart = max(record.startedAt, start ?? record.startedAt)
        let rangeEnd = min(record.endedAt, end ?? record.endedAt)
        guard rangeEnd > rangeStart else { return [] }

        let wall = record.endedAt.timeIntervalSince(record.startedAt)
        if wall <= 0 {
            return [
                Slice(
                    day: calendar.startOfDay(for: record.endedAt),
                    hour: calendar.component(.hour, from: record.endedAt),
                    taskTitle: task,
                    duration: record.actualDuration
                )
            ]
        }

        var result: [Slice] = []
        var cursor = rangeStart
        while cursor < rangeEnd {
            let hourEnd = calendar.dateInterval(of: .hour, for: cursor)?.end
                ?? cursor.addingTimeInterval(3600)
            let next = min(rangeEnd, hourEnd)
            let duration = record.actualDuration * next.timeIntervalSince(cursor) / wall
            if duration > 0 {
                result.append(
                    Slice(
                        day: calendar.startOfDay(for: cursor),
                        hour: calendar.component(.hour, from: cursor),
                        taskTitle: task,
                        duration: duration
                    )
                )
            }
            cursor = next
        }
        return result
    }

    static func slices(
        in records: [PomodoroSessionRecord],
        from start: Date? = nil,
        to end: Date? = nil,
        calendar: Calendar = beijingCalendar
    ) -> [Slice] {
        records.flatMap { slices($0, from: start, to: end, calendar: calendar) }
    }

    static func totalSeconds(
        in records: [PomodoroSessionRecord],
        from start: Date? = nil,
        to end: Date? = nil
    ) -> TimeInterval {
        let bounds: (start: Date, end: Date)?
        if let start, let end {
            bounds = (start, end)
        } else {
            bounds = nil
        }
        return records.reduce(0) { partial, record in
            guard isSavedFocus(record) else { return partial }
            return partial + clippedDuration(record, within: bounds)
        }
    }

    static func dailyTaskPoints(
        in records: [PomodoroSessionRecord],
        from start: Date? = nil,
        to end: Date? = nil,
        calendar: Calendar = beijingCalendar
    ) -> [PomodoroDailyFocusPoint] {
        var totals: [DayTask: TimeInterval] = [:]
        for slice in slices(in: records, from: start, to: end, calendar: calendar) {
            totals[DayTask(day: slice.day, taskTitle: slice.taskTitle), default: 0] += slice.duration
        }
        return totals.map { key, duration in
            PomodoroDailyFocusPoint(day: key.day, taskTitle: key.taskTitle, duration: duration)
        }
        .sorted { lhs, rhs in
            lhs.day == rhs.day ? lhs.taskTitle < rhs.taskTitle : lhs.day < rhs.day
        }
    }

    static func dailyTotals(
        in records: [PomodoroSessionRecord],
        from start: Date? = nil,
        to end: Date? = nil,
        calendar: Calendar = beijingCalendar
    ) -> [Date: TimeInterval] {
        var totals: [Date: TimeInterval] = [:]
        for slice in slices(in: records, from: start, to: end, calendar: calendar) {
            totals[slice.day, default: 0] += slice.duration
        }
        return totals
    }

    static func weekBounds(
        containing date: Date,
        calendar: Calendar = beijingCalendar
    ) -> (start: Date, end: Date) {
        let start = PomodoroHistoryRangePolicy.weekStart(containing: date, calendar: calendar)
        let end = calendar.date(byAdding: .day, value: 7, to: start)
            ?? start.addingTimeInterval(7 * 86_400)
        return (start, end)
    }

    static func weekDays(
        containing date: Date,
        calendar: Calendar = beijingCalendar
    ) -> [Date] {
        let start = weekBounds(containing: date, calendar: calendar).start
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    static func weekTaskPoints(
        in records: [PomodoroSessionRecord],
        containing date: Date,
        calendar: Calendar = beijingCalendar
    ) -> [PomodoroDailyFocusPoint] {
        let bounds = weekBounds(containing: date, calendar: calendar)
        return dailyTaskPoints(in: records, from: bounds.start, to: bounds.end, calendar: calendar)
    }

    static func weekDayMinutes(
        in records: [PomodoroSessionRecord],
        containing date: Date,
        calendar: Calendar = beijingCalendar
    ) -> [(day: Date, minutes: Double)] {
        let bounds = weekBounds(containing: date, calendar: calendar)
        let totals = dailyTotals(in: records, from: bounds.start, to: bounds.end, calendar: calendar)
        return weekDays(containing: date, calendar: calendar).map { day in
            (day: day, minutes: (totals[day] ?? 0) / 60)
        }
    }

    /// 统计页「近 N 天」的半开窗口，结束于明天 0 点。跟随中的学习记录必须用同一函数，不能把日期冻在切换当天。
    static func trailingDayWindow(
        days: Int,
        containing now: Date = Date(),
        calendar: Calendar = beijingCalendar
    ) -> (start: Date, end: Date) {
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
            ?? now.addingTimeInterval(86_400)
        let start = calendar.date(byAdding: .day, value: -max(days, 1), to: end) ?? end
        return (start, end)
    }

    /// 与今天有重叠的正计时：次数按记录计，时长按今天这段裁剪。
    static func stopwatchOverlap(
        in records: [PomodoroSessionRecord],
        from start: Date,
        to end: Date
    ) -> (count: Int, seconds: TimeInterval) {
        var count = 0
        var seconds: TimeInterval = 0
        for record in records where record.status == .stopwatch && record.actualDuration > 0 {
            let clipped = clippedDuration(record, within: (start, end))
            guard clipped > 0 else { continue }
            count += 1
            seconds += clipped
        }
        return (count, seconds)
    }

    static func todayBounds(
        containing date: Date = Date(),
        calendar: Calendar = beijingCalendar
    ) -> (start: Date, end: Date) {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start)
            ?? start.addingTimeInterval(86_400)
        return (start, end)
    }

    /// 严格晚于 `date` 的下一个北京时间零点。正好落在零点时返回再下一天，避免刷新日程把自己再次排进队列。
    static func nextDayBoundary(
        after date: Date,
        calendar: Calendar = beijingCalendar
    ) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: start)
            ?? start.addingTimeInterval(86_400)
    }

    /// 首页换日用的时刻。日程若给出两秒以后的未来时间，仍按时钟，避免把下一天提前显示出来。
    static func displayInstant(scheduleDate: Date, anchor: Date, clock: Date = Date()) -> Date {
        if scheduleDate > clock.addingTimeInterval(2) {
            return max(anchor, clock)
        }
        return max(scheduleDate, anchor, clock)
    }

    static func todayTaskMinutes(
        in records: [PomodoroSessionRecord],
        at date: Date = Date(),
        calendar: Calendar = beijingCalendar,
        limit: Int = 5
    ) -> [(title: String, minutes: Double)] {
        let bounds = todayBounds(containing: date, calendar: calendar)
        var totals: [String: Double] = [:]
        for point in dailyTaskPoints(in: records, from: bounds.start, to: bounds.end, calendar: calendar) {
            totals[point.taskTitle, default: 0] += point.duration / 60
        }
        return totals
            .filter { $0.value >= 1 }
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(limit)
            .map { (title: $0.key, minutes: $0.value) }
    }

    static func streakDays(
        in records: [PomodoroSessionRecord],
        at date: Date = Date(),
        calendar: Calendar = beijingCalendar,
        minimumSeconds: TimeInterval = 60
    ) -> Int {
        func duration(on dayStart: Date) -> TimeInterval {
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)
                ?? dayStart.addingTimeInterval(86_400)
            return totalSeconds(in: records, from: dayStart, to: dayEnd)
        }

        var cursor = calendar.startOfDay(for: date)
        if duration(on: cursor) < minimumSeconds {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            cursor = yesterday
        }
        var count = 0
        while duration(on: cursor) >= minimumSeconds {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    static func timeSlotMinutes(
        in records: [PomodoroSessionRecord],
        from start: Date,
        to end: Date,
        calendar: Calendar = beijingCalendar
    ) -> [(label: String, minutes: Double, icon: String)] {
        var buckets: [(label: String, minutes: Double, icon: String)] = [
            ("凌晨", 0, "moon.stars.fill"),
            ("上午", 0, "sunrise.fill"),
            ("下午", 0, "sun.max.fill"),
            ("晚上", 0, "moon.fill")
        ]
        for slice in slices(in: records, from: start, to: end, calendar: calendar) {
            let index: Int
            if slice.hour < 6 { index = 0 }
            else if slice.hour < 12 { index = 1 }
            else if slice.hour < 18 { index = 2 }
            else { index = 3 }
            buckets[index].minutes += slice.duration / 60
        }
        return buckets
    }

    static func weekPace(
        in records: [PomodoroSessionRecord],
        goalMinutes: Int,
        at date: Date = Date(),
        calendar: Calendar = beijingCalendar
    ) -> WeekPace {
        let bounds = weekBounds(containing: date, calendar: calendar)
        let saved = totalSeconds(in: records, from: bounds.start, to: bounds.end)
        let goalSeconds = max(3600, Double(max(1, goalMinutes) * 60))
        let remaining = max(0, goalSeconds - saved)
        let today = calendar.startOfDay(for: date)
        let dayIndex = max(0, min(6, calendar.dateComponents([.day], from: bounds.start, to: today).day ?? 0))
        let daysLeft = max(1, 7 - dayIndex)
        let dailyTarget = goalSeconds / 7
        let goalHours = max(1, Int((goalSeconds / 3600).rounded()))
        let headline: String
        if remaining <= 0 {
            headline = "已达成本周 \(goalHours) 小时目标"
        } else {
            let perDayHours = remaining / Double(daysLeft) / 3600
            headline = String(format: "按每天 %.1f 小时，本周内可达标", perDayHours)
        }
        return WeekPace(
            savedSeconds: saved,
            goalSeconds: goalSeconds,
            remainingSeconds: remaining,
            dailyTargetSeconds: dailyTarget,
            daysLeftIncludingToday: daysLeft,
            headline: headline
        )
    }

    static func durationText(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return minutes > 0 ? "\(hours) 小时 \(minutes) 分" : "\(hours) 小时"
        }
        return "\(minutes) 分钟"
    }

    /// 时段图用。`selectedTask == "全部科目"` 时保留全部；否则只留该科目。总量不要走这个函数。
    static func hourlySeconds(
        in records: [PomodoroSessionRecord],
        from start: Date,
        to end: Date,
        selectedTask: String,
        calendar: Calendar = beijingCalendar
    ) -> [Int: TimeInterval] {
        let rows = slices(in: records, from: start, to: end, calendar: calendar).filter { slice in
            selectedTask == "全部科目" || slice.taskTitle == selectedTask
        }
        var hours: [Int: TimeInterval] = [:]
        for row in rows {
            hours[row.hour, default: 0] += row.duration
        }
        return hours
    }

    /// 今天不和昨天全天算涨跌百分比。多日周期含未结束的今天时，写明对照的是更早的完整日。
    static func periodComparisonCaption(days: Int, previousSeconds: TimeInterval) -> String {
        let previous = durationText(previousSeconds)
        if days <= 1 {
            return "昨天全天 \(previous)"
        }
        return "对照更早 \(days) 个完整日共 \(previous)。本段含今天，今天尚未结束。"
    }

    /// 进行中的专注或正计时，只供界面提示，不写入历史。
    static func openSessionSeconds(_ state: PomodoroState, at date: Date) -> TimeInterval {
        if state.isStopwatchActive {
            return max(0, state.stopwatchElapsed(at: date))
        }
        if state.phase == .focus, state.sessionStartedAt != nil {
            return max(0, state.elapsed(at: date))
        }
        return 0
    }

    static func taskOrder(in points: [PomodoroDailyFocusPoint]) -> [String] {
        var totals: [String: TimeInterval] = [:]
        for point in points {
            totals[point.taskTitle, default: 0] += point.duration
        }
        return totals.sorted { lhs, rhs in
            lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
        }.map(\.key)
    }
}
