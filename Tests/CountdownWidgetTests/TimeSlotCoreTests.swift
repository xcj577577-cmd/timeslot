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

    func testColorHexNormalizationAndAlpha() throws {
        XCTAssertEqual(ColorHex.normalized(" aabbcc "), "#AABBCC")
        XCTAssertEqual(ColorHex.normalized("#11223380"), "#11223380")
        XCTAssertEqual(ColorHex.normalized("not-a-color"), ColorHex.fallback)
        XCTAssertFalse(ColorHex.isValid("#12345"))

        let rgba = try XCTUnwrap(ColorHex.rgba(from: "#11223380"))
        XCTAssertEqual(rgba.alpha, 128.0 / 255.0, accuracy: 0.0001)
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
