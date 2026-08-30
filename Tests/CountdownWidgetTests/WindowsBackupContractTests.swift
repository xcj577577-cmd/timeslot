import XCTest
@testable import CountdownWidget

/// Windows 兼容契约测试：docs/windows/DATA_FORMAT.md 描述的备份格式，
/// 其 fixture（docs/windows/fixtures/sample-backup-v1.json）必须能被真实的
/// Codable 类型解码。Windows 端实现以同一份 fixture 为对拍基准。
final class WindowsBackupContractTests: XCTestCase {
    private func fixtureURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests/CountdownWidgetTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // 仓库根目录
            .appendingPathComponent("docs/windows/fixtures/\(name)")
    }

    func testSampleBackupV1DecodesWithRealTypes() throws {
        let data = try Data(contentsOf: fixtureURL("sample-backup-v1.json"))
        let payload = try JSONDecoder().decode(BackupPayload.self, from: data)

        XCTAssertEqual(payload.schemaVersion, BackupPayload.currentSchemaVersion)
        XCTAssertEqual(payload.items.count, 2)
        XCTAssertEqual(payload.history.count, 2)
        XCTAssertEqual(payload.tasks.count, 2)
        XCTAssertEqual(payload.displayMode, "both")
        XCTAssertEqual(payload.timeUnit, "auto")
        XCTAssertEqual(payload.exportedAt, Date(timeIntervalSinceReferenceDate: 800_000_000))
    }

    func testCountdownPauseSemanticsSurviveRoundTrip() throws {
        let data = try Data(contentsOf: fixtureURL("sample-backup-v1.json"))
        let payload = try JSONDecoder().decode(BackupPayload.self, from: data)

        let running = try XCTUnwrap(payload.items.first { $0.pausedRemaining == nil })
        XCTAssertEqual(running.title, "项目上线")
        XCTAssertEqual(running.colorHex, "#2C8C7C")
        XCTAssertTrue(running.isPinned)

        let paused = try XCTUnwrap(payload.items.first { $0.pausedRemaining != nil })
        XCTAssertEqual(paused.pausedRemaining, 123456.5)
        XCTAssertFalse(paused.isPinned)
    }

    func testHistoryPhaseAndStatusEnumsMatchContract() throws {
        let data = try Data(contentsOf: fixtureURL("sample-backup-v1.json"))
        let payload = try JSONDecoder().decode(BackupPayload.self, from: data)

        XCTAssertTrue(payload.history.contains {
            $0.phase == .focus && $0.status == .completed && $0.taskTitle == "写作"
        })
        XCTAssertTrue(payload.history.contains { $0.status == .stopwatch })
    }

    func testPomodoroStateToleratesPartialPayload() throws {
        let data = try Data(contentsOf: fixtureURL("sample-backup-v1.json"))
        let payload = try JSONDecoder().decode(BackupPayload.self, from: data)

        // fixture 只写入了部分字段，其余必须回退到默认值
        XCTAssertEqual(payload.pomodoro.taskTitle, "写作")
        XCTAssertEqual(payload.pomodoro.weeklyFocusGoalMinutes, 600)
        XCTAssertEqual(payload.pomodoro.shortBreakMinutes, 5)
        XCTAssertFalse(payload.pomodoro.isRunning)
    }

    func testAppleReferenceEpochConversionMatchesDocumentation() {
        // DATA_FORMAT.md：Unix 秒 = Apple 秒 + 978307200
        let apple = 800_000_000.0
        XCTAssertEqual(
            Date(timeIntervalSinceReferenceDate: apple).timeIntervalSince1970,
            apple + 978_307_200,
            accuracy: 0.001
        )
    }
}
