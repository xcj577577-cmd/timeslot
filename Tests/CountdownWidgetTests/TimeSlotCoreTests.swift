import XCTest
@testable import CountdownWidget

final class TimeSlotCoreTests: XCTestCase {
    func testRunningPomodoroRemainingUsesAbsoluteEndDate() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000_000)
        var state = PomodoroState()
        state.focusMinutes = 25
        state.phase = .focus
        state.isRunning = true
        state.activeStartedAt = start
        state.sessionStartedAt = start
        state.endDate = start.addingTimeInterval(25 * 60)
        state.pausedRemaining = 25 * 60

        XCTAssertEqual(
            state.remaining(at: start.addingTimeInterval(10 * 60)),
            15 * 60,
            accuracy: 0.001
        )
    }

    func testPausedElapsedDoesNotDoubleCountPreviousActiveTime() {
        let start = Date(timeIntervalSinceReferenceDate: 2_000_000)
        var state = PomodoroState()
        state.focusMinutes = 30
        state.phase = .focus
        state.isRunning = false
        state.activeStartedAt = nil
        state.accumulatedElapsed = 12 * 60
        state.pausedRemaining = 18 * 60

        XCTAssertEqual(
            state.elapsed(at: start.addingTimeInterval(60 * 60)),
            12 * 60,
            accuracy: 0.001
        )
    }

    func testLateObservationUsesScheduledCompletionDate() {
        let scheduledEnd = Date(timeIntervalSinceReferenceDate: 3_000_000)
        var state = PomodoroState()
        state.endDate = scheduledEnd

        XCTAssertEqual(
            state.completionDate(whenObservedAt: scheduledEnd.addingTimeInterval(8 * 60 * 60)),
            scheduledEnd
        )
    }

    func testTaskFallbackColorIsStable() {
        XCTAssertEqual(
            PomodoroTaskPalette.fallbackColorHex(for: "高数"),
            PomodoroTaskPalette.fallbackColorHex(for: "高数")
        )
    }

    func testStopwatchElapsedAccumulatesWhileRunning() {
        let start = Date(timeIntervalSinceReferenceDate: 4_000_000)
        var state = PomodoroState()
        state.stopwatchSessionStartedAt = start
        state.stopwatchActiveStartedAt = start
        state.stopwatchRunning = true
        state.stopwatchAccumulated = 0

        XCTAssertEqual(
            state.stopwatchElapsed(at: start.addingTimeInterval(10 * 60)),
            10 * 60,
            accuracy: 0.001
        )
        XCTAssertTrue(state.isStopwatchActive)
    }

    func testStopwatchPausedKeepsElapsed() {
        let start = Date(timeIntervalSinceReferenceDate: 5_000_000)
        var state = PomodoroState()
        state.stopwatchSessionStartedAt = start
        state.stopwatchRunning = true
        state.stopwatchActiveStartedAt = start
        state.stopwatchAccumulated = 0

        let pausedAt = start.addingTimeInterval(5 * 60)
        state.stopwatchAccumulated = state.stopwatchElapsed(at: pausedAt)
        state.stopwatchRunning = false
        state.stopwatchActiveStartedAt = nil

        XCTAssertEqual(
            state.stopwatchElapsed(at: pausedAt.addingTimeInterval(60 * 60)),
            5 * 60,
            accuracy: 0.001
        )
    }

    func testStopwatchElapsedIncludesAccumulatedAndActive() {
        let start = Date(timeIntervalSinceReferenceDate: 6_000_000)
        var state = PomodoroState()
        state.stopwatchSessionStartedAt = start
        state.stopwatchAccumulated = 10 * 60
        state.stopwatchRunning = true
        state.stopwatchActiveStartedAt = start.addingTimeInterval(10 * 60)

        XCTAssertEqual(
            state.stopwatchElapsed(at: start.addingTimeInterval(15 * 60)),
            15 * 60,
            accuracy: 0.001
        )
    }

    func testStopwatchInactiveByDefault() {
        let state = PomodoroState()
        XCTAssertFalse(state.isStopwatchActive)
        XCTAssertEqual(state.stopwatchElapsed(at: Date()), 0, accuracy: 0.001)
    }

    func testWeeklyFocusGoalDefaultsToTenHours() {
        XCTAssertEqual(PomodoroState().weeklyFocusGoalMinutes, 10 * 60)
    }

    func testWeeklyFocusGoalRoundTripsThroughStateStorage() throws {
        var state = PomodoroState()
        state.weeklyFocusGoalMinutes = 14 * 60
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(PomodoroState.self, from: data)
        XCTAssertEqual(decoded.weeklyFocusGoalMinutes, 14 * 60)
    }

    func testLegacyPomodoroStateDecodesWithoutStopwatchFields() throws {
        // 旧版本存档没有正计时字段，载入时不能解码失败。
        let json = """
        {
          "taskTitle": "单词",
          "phase": "focus",
          "focusMinutes": 25,
          "shortBreakMinutes": 5,
          "longBreakMinutes": 15,
          "roundsBeforeLongBreak": 4,
          "completedFocusSessions": 2,
          "isRunning": true,
          "endDate": 1234567,
          "pausedRemaining": 1500,
          "sessionStartedAt": 1234567,
          "activeStartedAt": 1234567,
          "accumulatedElapsed": 0
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let state = try JSONDecoder().decode(PomodoroState.self, from: data)
        XCTAssertFalse(state.stopwatchRunning)
        XCTAssertFalse(state.isStopwatchActive)
        XCTAssertEqual(state.weeklyFocusGoalMinutes, 10 * 60)
        XCTAssertEqual(state.stopwatchElapsed(at: Date()), 0, accuracy: 0.001)
    }

    func testActiveCountdownSchedulesNotification() {
        let now = Date(timeIntervalSinceReferenceDate: 10_000_000)
        let item = CountdownItem(
            title: "发布",
            targetDate: now.addingTimeInterval(3600),
            colorHex: "#2C8C7C"
        )
        XCTAssertTrue(CountdownNotificationPolicy.shouldSchedule(item: item, at: now))
    }

    func testPausedCountdownDoesNotScheduleNotification() {
        let now = Date(timeIntervalSinceReferenceDate: 11_000_000)
        var item = CountdownItem(
            title: "休息",
            targetDate: now.addingTimeInterval(1800),
            colorHex: "#2C8C7C"
        )
        item.pausedRemaining = 900
        XCTAssertFalse(CountdownNotificationPolicy.shouldSchedule(item: item, at: now))
    }

    func testExpiredCountdownDoesNotScheduleNotification() {
        let now = Date(timeIntervalSinceReferenceDate: 12_000_000)
        let item = CountdownItem(
            title: "已结束",
            targetDate: now.addingTimeInterval(-60),
            colorHex: "#D86F52"
        )
        XCTAssertFalse(CountdownNotificationPolicy.shouldSchedule(item: item, at: now))
    }

    func testBeijingDateStringUsesUTC8() {
        let fixed = Date(timeIntervalSince1970: 1_752_000_000)
        let formatted = beijingDateString(
            fixed,
            dateStyle: .long,
            timeStyle: .shortened
        )
        // 1752000000 = 2025-07-08 18:40 UTC = 北京 2025-07-09 02:40
        XCTAssertTrue(formatted.contains("2:40"), formatted)
    }
}


// MARK: - 备份与数据安全

extension TimeSlotCoreTests {
    func testBackupPayloadRoundTrip() throws {
        let now = Date(timeIntervalSinceReferenceDate: 9_000_000)
        let item = CountdownItem(title: "测试", targetDate: now.addingTimeInterval(3600), colorHex: "#2C8C7C", isPinned: true)
        let task = PomodoroTask(title: "高数")
        let payload = BackupPayload(
            items: [item],
            pomodoro: PomodoroState(),
            history: [],
            tasks: [task],
            displayMode: "both",
            timeUnit: "days",
            exportedAt: now
        )
        let data = try JSONEncoder().encode(payload)
        let decoded = try CountdownStore.decodeBackup(data)
        XCTAssertEqual(decoded.items, [item])
        XCTAssertEqual(decoded.pomodoro, PomodoroState())
        XCTAssertEqual(decoded.tasks.first?.title, task.title)
        XCTAssertEqual(decoded.tasks.first?.colorHex, task.colorHex)
        XCTAssertEqual(decoded.displayMode, "both")
        XCTAssertEqual(decoded.timeUnit, "days")
    }

    func testBeijingCalendarMidnightBoundary() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let beijingMidnight = beijingCalendar.date(from: DateComponents(
            year: 2026, month: 8, day: 1, hour: 0, minute: 0, second: 0
        ))!
        let utcComponents = utc.dateComponents([.year, .month, .day, .hour], from: beijingMidnight)
        XCTAssertEqual(utcComponents.year, 2026)
        XCTAssertEqual(utcComponents.month, 7)
        XCTAssertEqual(utcComponents.day, 31)
        XCTAssertEqual(utcComponents.hour, 16)
    }

    func testCountdownRemainingWhenPaused() {
        let start = Date(timeIntervalSinceReferenceDate: 7_000_000)
        var item = CountdownItem(
            title: "测试",
            targetDate: start.addingTimeInterval(3600),
            colorHex: "#2C8C7C",
            isPinned: true
        )
        item.pausedRemaining = 1200
        XCTAssertEqual(item.remaining(at: start.addingTimeInterval(7200)), 1200, accuracy: 0.001)
    }

    func testCountdownRemainingPastTarget() {
        let start = Date(timeIntervalSinceReferenceDate: 8_000_000)
        let item = CountdownItem(
            title: "测试",
            targetDate: start.addingTimeInterval(60),
            colorHex: "#2C8C7C"
        )
        XCTAssertEqual(item.remaining(at: start.addingTimeInterval(120)), 0, accuracy: 0.001)
    }
}
