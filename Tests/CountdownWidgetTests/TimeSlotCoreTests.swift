import XCTest
@testable import CountdownWidget

final class TimeSlotCoreTests: XCTestCase {
    func testLocalStorageMigrationRequiresUnversionedAndOlderData() {
        XCTAssertTrue(LocalStorageMigration.needsMigration(storedVersion: nil))
        XCTAssertTrue(LocalStorageMigration.needsMigration(storedVersion: 1))
        XCTAssertFalse(LocalStorageMigration.needsMigration(
            storedVersion: LocalStorageMigration.currentSchemaVersion
        ))
    }

    func testStorageMigrationStateCommunicatesSnapshotOutcome() {
        XCTAssertEqual(StorageMigrationState.current.title, "本地数据正常")
        XCTAssertTrue(StorageMigrationState.migrated(from: nil).subtitle.contains("首次数据整理"))
        XCTAssertEqual(
            StorageMigrationState.pending("稍后重试").subtitle,
            "稍后重试"
        )
    }

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

    func testPomodoroTimerModePolicyKeepsActiveStopwatchVisible() {
        let now = Date(timeIntervalSinceReferenceDate: 7_000_000)
        var state = PomodoroState()
        state.stopwatchRunning = true
        state.stopwatchSessionStartedAt = now
        state.stopwatchActiveStartedAt = now

        XCTAssertEqual(
            PomodoroTimerModePolicy.initialMode(storedMode: .countdown, state: state),
            .stopwatch
        )
        XCTAssertFalse(PomodoroTimerModePolicy.canSwitchMode(for: state))
    }

    func testPomodoroTimerModePolicyKeepsActiveCountdownVisible() {
        let now = Date(timeIntervalSinceReferenceDate: 8_000_000)
        var state = PomodoroState()
        state.isRunning = true
        state.sessionStartedAt = now
        state.activeStartedAt = now
        state.endDate = now.addingTimeInterval(25 * 60)

        XCTAssertEqual(
            PomodoroTimerModePolicy.initialMode(storedMode: .stopwatch, state: state),
            .countdown
        )
        XCTAssertFalse(PomodoroTimerModePolicy.canSwitchMode(for: state))
    }

    func testPomodoroTimerModePolicyUsesPreferenceOnlyWhenIdle() {
        let state = PomodoroState()

        XCTAssertEqual(
            PomodoroTimerModePolicy.initialMode(storedMode: .stopwatch, state: state),
            .stopwatch
        )
        XCTAssertTrue(PomodoroTimerModePolicy.canSwitchMode(for: state))
    }

    func testPomodoroQuickPresetsFollowCurrentPhase() {
        XCTAssertEqual(PomodoroPresets.quick(for: .focus), [25, 45, 60, 90])
        XCTAssertEqual(PomodoroPresets.quick(for: .shortBreak), [3, 5, 10, 15])
        XCTAssertEqual(PomodoroPresets.quick(for: .longBreak), [10, 15, 20, 30])
    }

    func testPomodoroDurationSettingsReplacesOnlyCurrentPhase() {
        var state = PomodoroState()
        state.focusMinutes = 60
        state.shortBreakMinutes = 5
        state.longBreakMinutes = 15

        let updated = PomodoroDurationSettings(state: state)
            .replacingDuration(for: .shortBreak, with: 10)

        XCTAssertEqual(updated.focusMinutes, 60)
        XCTAssertEqual(updated.shortBreakMinutes, 10)
        XCTAssertEqual(updated.longBreakMinutes, 15)
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

    func testHistoryWeekBoundsUseBeijingMondayToSunday() throws {
        let selectedDate = try XCTUnwrap(beijingCalendar.date(from: DateComponents(
            year: 2026, month: 8, day: 19, hour: 12
        )))
        let expectedStart = try XCTUnwrap(beijingCalendar.date(from: DateComponents(
            year: 2026, month: 8, day: 17
        )))
        let expectedEnd = try XCTUnwrap(beijingCalendar.date(from: DateComponents(
            year: 2026, month: 8, day: 24
        )))

        let bounds = try XCTUnwrap(PomodoroHistoryRangePolicy.bounds(
            for: .week,
            now: selectedDate,
            selectedWeekStart: selectedDate,
            customStart: selectedDate,
            customEnd: selectedDate
        ))

        XCTAssertEqual(bounds.start, expectedStart)
        XCTAssertEqual(bounds.end, expectedEnd)
    }

    func testHistoryWeekPresetsIncludeCurrentAndRecordedWeeksOnce() throws {
        let now = try XCTUnwrap(beijingCalendar.date(from: DateComponents(
            year: 2026, month: 8, day: 19, hour: 12
        )))
        let recordedDates = try [
            DateComponents(year: 2026, month: 8, day: 12, hour: 9),
            DateComponents(year: 2026, month: 8, day: 10, hour: 20),
            DateComponents(year: 2026, month: 8, day: 3, hour: 8)
        ].map { components in
            try XCTUnwrap(beijingCalendar.date(from: components))
        }
        let expected = try [
            DateComponents(year: 2026, month: 8, day: 17),
            DateComponents(year: 2026, month: 8, day: 10),
            DateComponents(year: 2026, month: 8, day: 3)
        ].map { components in
            try XCTUnwrap(beijingCalendar.date(from: components))
        }

        XCTAssertEqual(
            PomodoroHistoryRangePolicy.availableWeekStarts(
                recordDates: recordedDates,
                now: now
            ),
            expected
        )
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

    func testColorHexNormalizationAndAlpha() throws {
        XCTAssertEqual(ColorHex.normalized(" aabbcc "), "#AABBCC")
        XCTAssertEqual(ColorHex.normalized("#11223380"), "#11223380")
        XCTAssertEqual(ColorHex.normalized("not-a-color"), ColorHex.fallback)
        XCTAssertFalse(ColorHex.isValid("#12345"))

        let rgba = try XCTUnwrap(ColorHex.rgba(from: "#11223380"))
        XCTAssertEqual(rgba.alpha, 128.0 / 255.0, accuracy: 0.0001)
    }

    func testDataSignalMapsLegacyColorsWithoutChangingUnknownValues() {
        XCTAssertEqual(DataSignal.presentationHex(for: "#2c8c7c"), "#55A99C")
        XCTAssertEqual(DataSignal.presentationHex(for: "#123456"), "#123456")
    }

    func testCountdownItemNormalizesUntrustedFields() {
        let longTitle = "  " + String(repeating: "时", count: 100) + "  "
        let item = CountdownItem(
            title: longTitle,
            targetDate: Date().addingTimeInterval(60),
            colorHex: "broken"
        )
        XCTAssertEqual(item.title.count, 80)
        XCTAssertEqual(item.colorHex, ColorHex.fallback)
    }

    func testExplicitlyEmptyCountdownStorageStaysEmpty() throws {
        let data = try JSONEncoder().encode([CountdownItem]())
        XCTAssertEqual(CountdownItemsStoragePolicy.resolve(data), .decoded([]))
        XCTAssertEqual(CountdownItemsStoragePolicy.resolve(nil), .missing)
        XCTAssertEqual(
            CountdownItemsStoragePolicy.resolve(Data("broken".utf8)),
            .corrupted
        )
    }

    func testCorruptedPomodoroStateIsClampedAndRepaired() throws {
        let json = """
        {
          "taskTitle": "   ",
          "phase": "focus",
          "focusMinutes": 0,
          "shortBreakMinutes": -5,
          "longBreakMinutes": 999,
          "roundsBeforeLongBreak": 0,
          "weeklyFocusGoalMinutes": 0,
          "completedFocusSessions": -12,
          "isRunning": true,
          "pausedRemaining": -30,
          "accumulatedElapsed": 999999,
          "stopwatchRunning": true,
          "stopwatchAccumulated": -10
        }
        """
        let state = try JSONDecoder().decode(PomodoroState.self, from: Data(json.utf8))

        XCTAssertEqual(state.taskTitle, PomodoroTaskPalette.fallbackTitle)
        XCTAssertEqual(state.focusMinutes, 1)
        XCTAssertEqual(state.shortBreakMinutes, 1)
        XCTAssertEqual(state.longBreakMinutes, 60)
        XCTAssertEqual(state.roundsBeforeLongBreak, 2)
        XCTAssertEqual(state.weeklyFocusGoalMinutes, 60)
        XCTAssertEqual(state.completedFocusSessions, 0)
        XCTAssertEqual(state.pausedRemaining, 0)
        XCTAssertEqual(state.accumulatedElapsed, 60)
        XCTAssertEqual(state.stopwatchAccumulated, 0)
        XCTAssertFalse(state.isRunning)
        XCTAssertFalse(state.stopwatchRunning)
    }

    func testPomodoroNormalizationPreventsTwoRunningTimers() {
        let now = Date(timeIntervalSinceReferenceDate: 13_000_000)
        var state = PomodoroState()
        state.isRunning = true
        state.endDate = now.addingTimeInterval(600)
        state.sessionStartedAt = now
        state.activeStartedAt = now
        state.stopwatchRunning = true
        state.stopwatchSessionStartedAt = now
        state.stopwatchActiveStartedAt = now

        state.normalizeForRuntime()

        XCTAssertFalse(state.isRunning)
        XCTAssertNil(state.endDate)
        XCTAssertTrue(state.stopwatchRunning)
        XCTAssertNotNil(state.stopwatchActiveStartedAt)
    }

    func testPomodoroTaskTitleIsCappedAtFortyCharacters() {
        let task = PomodoroTask(title: String(repeating: "专", count: 80))
        XCTAssertEqual(task.title.count, 40)
    }

    func testManagedNotificationIdentifiersAreScoped() {
        let id = UUID(uuidString: "8B3F43CF-BBC8-4F5B-9A2E-45B81E4F3998")!
        XCTAssertTrue(TimeSlotNotificationIdentifier.isManaged(TimeSlotNotificationIdentifier.pomodoroPhaseEnd))
        XCTAssertTrue(TimeSlotNotificationIdentifier.isManaged("pomodoro.phase.end.legacy"))
        XCTAssertTrue(
            TimeSlotNotificationIdentifier.isManaged(
                TimeSlotNotificationIdentifier.countdownCompletion(for: id)
            )
        )
        XCTAssertFalse(TimeSlotNotificationIdentifier.isManaged("another-app.notification"))
    }

    func testLegacyBackupWithoutSchemaOrOptionalCollectionsImports() throws {
        let payload = BackupPayload(
            items: [],
            pomodoro: PomodoroState(),
            history: [],
            tasks: [],
            displayMode: "both",
            timeUnit: "auto",
            exportedAt: Date(timeIntervalSinceReferenceDate: 14_000_000)
        )
        let encoded = try JSONEncoder().encode(payload)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        for key in ["schemaVersion", "history", "tasks", "displayMode", "timeUnit", "exportedAt"] {
            object.removeValue(forKey: key)
        }

        let decoded = try CountdownStore.decodeBackup(
            JSONSerialization.data(withJSONObject: object)
        )
        XCTAssertEqual(decoded.schemaVersion, BackupPayload.currentSchemaVersion)
        XCTAssertTrue(decoded.items.isEmpty)
        XCTAssertTrue(decoded.history.isEmpty)
        XCTAssertTrue(decoded.tasks.isEmpty)
        XCTAssertEqual(decoded.displayMode, "both")
        XCTAssertEqual(decoded.timeUnit, "auto")
    }

    func testBackupRejectsFutureAndInvalidSchemas() throws {
        for version in [0, BackupPayload.currentSchemaVersion + 1] {
            let payload = BackupPayload(
                schemaVersion: version,
                items: [],
                pomodoro: PomodoroState(),
                history: [],
                tasks: [],
                displayMode: "both",
                timeUnit: "auto",
                exportedAt: Date()
            )
            let data = try JSONEncoder().encode(payload)
            XCTAssertThrowsError(try CountdownStore.decodeBackup(data)) { error in
                XCTAssertEqual(error as? BackupValidationError, .unsupportedSchema(version))
            }
        }
    }

    func testBackupRejectsOversizedFileBeforeDecoding() {
        let data = Data(
            repeating: 0,
            count: BackupValidationPolicy.maximumFileSize + 1
        )
        XCTAssertThrowsError(try CountdownStore.decodeBackup(data)) { error in
            XCTAssertEqual(error as? BackupValidationError, .fileTooLarge)
        }
    }
}


// MARK: - 专注统计口径（只读，合成记录，不读 App Group）

extension TimeSlotCoreTests {
    private func beijingDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 0,
        minute: Int = 0
    ) throws -> Date {
        try XCTUnwrap(beijingCalendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute
        )))
    }

    private func focusRecord(
        title: String,
        start: Date,
        end: Date,
        actual: TimeInterval? = nil,
        phase: PomodoroPhase = .focus
    ) -> PomodoroSessionRecord {
        let wall = end.timeIntervalSince(start)
        return PomodoroSessionRecord(
            phase: phase,
            taskTitle: title,
            plannedDuration: wall,
            actualDuration: actual ?? wall,
            startedAt: start,
            endedAt: end,
            status: .completed
        )
    }

    func testFocusStatsSplitsOvernightRecordAcrossBeijingDays() throws {
        let start = try beijingDate(year: 2026, month: 9, day: 21, hour: 23)
        let end = try beijingDate(year: 2026, month: 9, day: 22, hour: 1)
        let record = focusRecord(title: "数学", start: start, end: end)
        let slices = FocusStats.slices(record)
        let monday = beijingCalendar.startOfDay(for: start)
        let tuesday = beijingCalendar.startOfDay(for: end)
        let mondaySeconds = slices.filter { $0.day == monday }.reduce(0) { $0 + $1.duration }
        let tuesdaySeconds = slices.filter { $0.day == tuesday }.reduce(0) { $0 + $1.duration }
        XCTAssertEqual(mondaySeconds, 3600, accuracy: 0.01)
        XCTAssertEqual(tuesdaySeconds, 3600, accuracy: 0.01)
        XCTAssertEqual(FocusStats.totalSeconds(in: [record]), 7200, accuracy: 0.01)
    }

    func testFocusStatsSplitsAcrossMondayWeekBoundary() throws {
        let start = try beijingDate(year: 2026, month: 9, day: 20, hour: 23)
        let end = try beijingDate(year: 2026, month: 9, day: 21, hour: 1)
        let record = focusRecord(title: "英语", start: start, end: end)
        let sundayWeek = FocusStats.weekBounds(containing: start)
        let mondayWeek = FocusStats.weekBounds(containing: end)
        XCTAssertEqual(sundayWeek.end, mondayWeek.start)
        XCTAssertEqual(
            FocusStats.totalSeconds(in: [record], from: sundayWeek.start, to: sundayWeek.end),
            3600,
            accuracy: 0.01
        )
        XCTAssertEqual(
            FocusStats.totalSeconds(in: [record], from: mondayWeek.start, to: mondayWeek.end),
            3600,
            accuracy: 0.01
        )
    }

    func testFocusStatsPausedSessionUsesActualOverWallRatio() throws {
        let start = try beijingDate(year: 2026, month: 9, day: 21, hour: 22)
        let end = try beijingDate(year: 2026, month: 9, day: 22, hour: 1)
        let record = focusRecord(title: "431", start: start, end: end, actual: 3600)
        let monday = beijingCalendar.startOfDay(for: start)
        let tuesday = beijingCalendar.startOfDay(for: end)
        let points = FocusStats.dailyTaskPoints(in: [record])
        let mondayDuration = points.first { $0.day == monday }?.duration ?? 0
        let tuesdayDuration = points.first { $0.day == tuesday }?.duration ?? 0
        XCTAssertEqual(mondayDuration, 2400, accuracy: 0.01)
        XCTAssertEqual(tuesdayDuration, 1200, accuracy: 0.01)
        XCTAssertEqual(mondayDuration + tuesdayDuration, 3600, accuracy: 0.01)
    }

    func testFocusStatsIgnoresBreaksAndDoesNotCountLiveSessions() throws {
        let start = try beijingDate(year: 2026, month: 9, day: 21, hour: 10)
        let end = start.addingTimeInterval(1800)
        let focus = focusRecord(title: "数学", start: start, end: end)
        let rest = focusRecord(
            title: "数学",
            start: end,
            end: end.addingTimeInterval(300),
            phase: .shortBreak
        )
        XCTAssertEqual(FocusStats.totalSeconds(in: [focus, rest]), 1800, accuracy: 0.01)
        XCTAssertTrue(FocusStats.slices(rest).isEmpty)
    }

    func testFocusStatsClippedDurationMatchesHistoryCardOverlap() throws {
        let start = try beijingDate(year: 2026, month: 9, day: 21, hour: 23, minute: 30)
        let end = try beijingDate(year: 2026, month: 9, day: 22, hour: 0, minute: 30)
        let record = focusRecord(title: "线代", start: start, end: end)
        let day = beijingCalendar.startOfDay(for: end)
        let next = try beijingDate(year: 2026, month: 9, day: 23)
        XCTAssertEqual(
            FocusStats.clippedDuration(record, within: (day, next)),
            1800,
            accuracy: 0.01
        )
    }

    func testFocusStatsWeekPaceHeadlineWhenBehindTarget() throws {
        let monday = try beijingDate(year: 2026, month: 9, day: 21, hour: 9)
        let record = focusRecord(
            title: "数学",
            start: monday,
            end: monday.addingTimeInterval(2 * 3600)
        )
        let pace = FocusStats.weekPace(
            in: [record],
            goalMinutes: 56 * 60,
            at: monday
        )
        XCTAssertEqual(pace.savedSeconds, 7200, accuracy: 0.01)
        XCTAssertEqual(pace.daysLeftIncludingToday, 7)
        XCTAssertTrue(pace.headline.contains("每天"))
        XCTAssertFalse(pace.headline.contains("已达成"))
    }

    func testHourlyTotalsRespectSubjectFilter() throws {
        let start = try beijingDate(year: 2026, month: 9, day: 23, hour: 9)
        let math = focusRecord(title: "数学", start: start, end: start.addingTimeInterval(3600))
        let english = focusRecord(
            title: "英语",
            start: start.addingTimeInterval(3600),
            end: start.addingTimeInterval(7200)
        )
        let day = beijingCalendar.startOfDay(for: start)
        let next = try beijingDate(year: 2026, month: 9, day: 24)
        let mathHours = FocusStats.hourlySeconds(
            in: [math, english], from: day, to: next, selectedTask: "数学"
        )
        let allHours = FocusStats.hourlySeconds(
            in: [math, english], from: day, to: next, selectedTask: "全部科目"
        )
        XCTAssertEqual(mathHours.values.reduce(0, +), 3600, accuracy: 0.01)
        XCTAssertEqual(allHours.values.reduce(0, +), 7200, accuracy: 0.01)
    }

    func testDailyPointsAggregateHoursAndKeepUniqueIDs() throws {
        let morning = try beijingDate(year: 2026, month: 9, day: 23, hour: 9)
        let first = focusRecord(title: "数学", start: morning, end: morning.addingTimeInterval(3600))
        let second = focusRecord(
            title: "数学",
            start: morning.addingTimeInterval(2 * 3600),
            end: morning.addingTimeInterval(3 * 3600)
        )
        let english = focusRecord(
            title: "英语",
            start: morning.addingTimeInterval(4 * 3600),
            end: morning.addingTimeInterval(5 * 3600)
        )
        let day = beijingCalendar.startOfDay(for: morning)
        let next = try beijingDate(year: 2026, month: 9, day: 24)
        let points = FocusStats.dailyTaskPoints(in: [first, second, english], from: day, to: next)
        XCTAssertEqual(Set(points.map(\.id)).count, points.count)
        let math = try XCTUnwrap(points.first { $0.taskTitle == "数学" })
        XCTAssertEqual(math.duration, 7200, accuracy: 0.01)
        XCTAssertEqual(points.reduce(0) { $0 + $1.duration }, 3 * 3600, accuracy: 0.01)
        let onlyMath = points.filter { $0.taskTitle == "数学" }
        XCTAssertEqual(onlyMath.reduce(0) { $0 + $1.duration }, 7200, accuracy: 0.01)
    }

    func testDailyPointsKeepOvernightAndPausedDurations() throws {
        let start = try beijingDate(year: 2026, month: 9, day: 23, hour: 23)
        let end = try beijingDate(year: 2026, month: 9, day: 24, hour: 1)
        let paused = focusRecord(title: "数学", start: start, end: end, actual: 3600)
        let points = FocusStats.dailyTaskPoints(in: [paused])
        XCTAssertEqual(Set(points.map(\.id)).count, points.count)
        XCTAssertEqual(points.reduce(0) { $0 + $1.duration }, 3600, accuracy: 0.01)
        XCTAssertEqual(points.count, 2)
    }

    func testHistoryEditPreviewMatchesSavedActualAndKeepsTaskOnlyEdits() throws {
        let start = try beijingDate(year: 2026, month: 9, day: 23, hour: 10)
        let end = start.addingTimeInterval(59 * 60)
        let paused = focusRecord(title: "数学", start: start, end: end, actual: 27 * 60 + 18)
        let unchanged = try XCTUnwrap(PomodoroHistoryEditMath.preview(
            previous: paused, startedAt: start, endedAt: end
        ))
        XCTAssertEqual(unchanged.actual, 27 * 60 + 18, accuracy: 0.01)
        XCTAssertTrue(unchanged.timesUnchanged)
        XCTAssertEqual(unchanged.startedAt, start)
        XCTAssertEqual(unchanged.endedAt, end)

        let driftedEnd = end.addingTimeInterval(20)
        let secondsOnly = try XCTUnwrap(PomodoroHistoryEditMath.preview(
            previous: paused, startedAt: start, endedAt: driftedEnd
        ))
        XCTAssertEqual(secondsOnly.actual, paused.actualDuration, accuracy: 0.01)

        let longerEnd = end.addingTimeInterval(59 * 60)
        let stretched = try XCTUnwrap(PomodoroHistoryEditMath.preview(
            previous: paused, startedAt: start, endedAt: longerEnd
        ))
        XCTAssertEqual(stretched.actual, paused.actualDuration * 2, accuracy: 0.01)
        XCTAssertFalse(stretched.timesUnchanged)

        let plain = focusRecord(title: "英语", start: start, end: end, actual: 59 * 60)
        let plainStretched = try XCTUnwrap(PomodoroHistoryEditMath.preview(
            previous: plain, startedAt: start, endedAt: longerEnd
        ))
        XCTAssertEqual(plainStretched.actual, longerEnd.timeIntervalSince(start), accuracy: 0.01)
        XCTAssertNil(PomodoroHistoryEditMath.preview(
            previous: plain, startedAt: end, endedAt: start
        ))
    }

    func testTrailingWindowFollowsMidnightInsteadOfFrozenCustomDates() throws {
        let morning = try beijingDate(year: 2026, month: 9, day: 24, hour: 0, minute: 30)
        let window = FocusStats.trailingDayWindow(days: 30, containing: morning)
        let expectedStart = try beijingDate(year: 2026, month: 8, day: 26)
        let expectedEnd = try beijingDate(year: 2026, month: 9, day: 25)
        XCTAssertEqual(window.start, expectedStart)
        XCTAssertEqual(window.end, expectedEnd)
    }

    func testStopwatchOverlapCountsPortionThatFallsToday() throws {
        let start = try beijingDate(year: 2026, month: 9, day: 23, hour: 23, minute: 30)
        let end = try beijingDate(year: 2026, month: 9, day: 24, hour: 0, minute: 30)
        var record = focusRecord(title: "数学", start: start, end: end)
        record = PomodoroSessionRecord(
            id: record.id,
            phase: .focus,
            taskTitle: record.taskTitle,
            plannedDuration: record.plannedDuration,
            actualDuration: record.actualDuration,
            startedAt: record.startedAt,
            endedAt: record.endedAt,
            status: .stopwatch
        )
        let today = try beijingDate(year: 2026, month: 9, day: 24)
        let next = try beijingDate(year: 2026, month: 9, day: 25)
        let overlap = FocusStats.stopwatchOverlap(in: [record], from: today, to: next)
        XCTAssertEqual(overlap.count, 1)
        XCTAssertEqual(overlap.seconds, 30 * 60, accuracy: 0.01)
    }

    func testNextDayBoundaryRollsSavedTotalsOntoTheNewBeijingDay() throws {
        let evening = try beijingDate(year: 2026, month: 9, day: 23, hour: 23, minute: 30)
        let boundary = FocusStats.nextDayBoundary(after: evening)
        XCTAssertEqual(boundary, try beijingDate(year: 2026, month: 9, day: 24))
        XCTAssertEqual(
            FocusStats.nextDayBoundary(after: boundary),
            try beijingDate(year: 2026, month: 9, day: 25)
        )
        XCTAssertEqual(
            FocusStats.nextDayBoundary(after: boundary.addingTimeInterval(0.4)),
            try beijingDate(year: 2026, month: 9, day: 25)
        )

        let record = focusRecord(
            title: "数学",
            start: try beijingDate(year: 2026, month: 9, day: 23, hour: 21),
            end: try beijingDate(year: 2026, month: 9, day: 23, hour: 22)
        )
        let yesterday = FocusStats.todayBounds(containing: evening)
        let today = FocusStats.todayBounds(containing: boundary)
        XCTAssertEqual(
            FocusStats.totalSeconds(in: [record], from: yesterday.start, to: yesterday.end),
            3600,
            accuracy: 0.01
        )
        XCTAssertEqual(
            FocusStats.totalSeconds(in: [record], from: today.start, to: today.end),
            0,
            accuracy: 0.01
        )

        let sundayNight = try beijingDate(year: 2026, month: 8, day: 23, hour: 23, minute: 30)
        let monday = FocusStats.nextDayBoundary(after: sundayNight)
        let sundayRecord = focusRecord(
            title: "英语",
            start: try beijingDate(year: 2026, month: 8, day: 23, hour: 10),
            end: try beijingDate(year: 2026, month: 8, day: 23, hour: 11)
        )
        let before = FocusStats.weekPace(in: [sundayRecord], goalMinutes: 3000, at: sundayNight)
        let after = FocusStats.weekPace(in: [sundayRecord], goalMinutes: 3000, at: monday)
        XCTAssertEqual(before.savedSeconds, 3600, accuracy: 0.01)
        XCTAssertEqual(after.savedSeconds, 0, accuracy: 0.01)
    }

    func testDisplayInstantIgnoresAFutureScheduleEntry() throws {
        let clock = try beijingDate(year: 2026, month: 9, day: 23, hour: 23, minute: 30)
        let future = try beijingDate(year: 2026, month: 9, day: 24)
        let shown = FocusStats.displayInstant(
            scheduleDate: future,
            anchor: Date.distantPast,
            clock: clock
        )
        XCTAssertEqual(shown, clock)

        let earlyClock = future.addingTimeInterval(-0.4)
        let rolled = FocusStats.displayInstant(
            scheduleDate: future,
            anchor: Date.distantPast,
            clock: earlyClock
        )
        XCTAssertEqual(rolled, future)
    }

    func testBeijingDayScheduleStartsAtTheRequestThenHitsMidnight() throws {
        let now = try beijingDate(year: 2026, month: 9, day: 23, hour: 23, minute: 30)
        let entries = Array(BeijingDaySchedule().entries(from: now, mode: .normal).prefix(3))
        XCTAssertEqual(entries, [
            now,
            try beijingDate(year: 2026, month: 9, day: 24),
            try beijingDate(year: 2026, month: 9, day: 25)
        ])

        let midnight = try beijingDate(year: 2026, month: 9, day: 24)
        let fromMidnight = Array(BeijingDaySchedule().entries(from: midnight, mode: .lowFrequency).prefix(2))
        XCTAssertEqual(fromMidnight[0], midnight)
        XCTAssertEqual(fromMidnight[1], try beijingDate(year: 2026, month: 9, day: 25))
    }

    func testTimelineBlockIdentitySeparatesRecordsWithTheSameStart() throws {
        let day = try beijingDate(year: 2026, month: 9, day: 23, hour: 9)
        let one = UUID()
        let two = UUID()
        let left = TimelineBlockIdentity.make(recordIDs: [one], day: day, startHour: 9, live: false)
        let right = TimelineBlockIdentity.make(recordIDs: [two], day: day, startHour: 9, live: false)
        XCTAssertNotEqual(left, right)
        XCTAssertEqual(
            TimelineBlockIdentity.make(recordIDs: [one], day: day, startHour: 9, live: false),
            left
        )
    }
}
