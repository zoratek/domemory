//
//  LeaderboardServiceTests.swift
//  DoMemoryTests
//

import XCTest
@testable import DoMemory

/// Reads the fixture both platforms test against, so iOS can't drift from Android.
final class LeaderboardContractTests: XCTestCase {
    private func fixture() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // DoMemoryTests
            .deletingLastPathComponent() // DoMemory
            .deletingLastPathComponent() // ios
            .deletingLastPathComponent() // repository root
            .appendingPathComponent("firebase/fixtures/leaderboard-v1.json")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        return try XCTUnwrap(object as? [String: Any])
    }

    private func cases(_ key: String) throws -> [[String: Any]] {
        try XCTUnwrap(fixture()[key] as? [[String: Any]])
    }

    func testWordListsMatchTheFixtureInOrder() throws {
        let fixture = try fixture()
        XCTAssertEqual(LeaderboardNames.adjectives, fixture["adjectives"] as? [String])
        XCTAssertEqual(LeaderboardNames.animals, fixture["animals"] as? [String])
    }

    func testDefaultNamesMatchTheFixture() throws {
        for item in try cases("defaultNames") {
            let uid = try XCTUnwrap(item["uid"] as? String)
            let words = LeaderboardNames.defaultWords(uid: uid)
            XCTAssertEqual(words.adjective, item["a"] as? Int, uid)
            XCTAssertEqual(words.animal, item["b"] as? Int, uid)
            let name = "\(LeaderboardNames.adjectives[words.adjective]) \(LeaderboardNames.animals[words.animal])"
            XCTAssertEqual(name, item["englishName"] as? String, uid)
        }
    }

    func testRowOrderMatchesTheFixture() throws {
        let ordering = try XCTUnwrap(fixture()["ordering"] as? [String: Any])
        let rows = try XCTUnwrap(ordering["rows"] as? [[String: Any]]).compactMap { item -> LeaderboardRow? in
            guard let uid = item["uid"] as? String else { return nil }
            return LeaderboardRow(uid: uid, value: item)
        }
        XCTAssertEqual(rows.count, 4)
        XCTAssertEqual(LeaderboardRow.ranked(rows).map(\.uid), ordering["expectedOrder"] as? [String])
    }

    func testPointsToTopBoardMatchTheFixture() throws {
        for item in try cases("starsToTopBoard") {
            XCTAssertEqual(
                LeaderboardRow.pointsToTopBoard(
                    boardSize: try XCTUnwrap(item["boardSize"] as? Int),
                    lastRowScore: try XCTUnwrap(item["lastRowScore"] as? Int),
                    ownScore: try XCTUnwrap(item["ownScore"] as? Int)
                ),
                item["expected"] as? Int
            )
        }
    }

    func testStarAwardsMatchTheFixture() throws {
        let defaults = UserDefaults.standard
        let keys = ["levels.highestUnlocked", "levels.lifetimeStars", "levels.wallet.balance"]
        let levels = 900..<920
        func reset() {
            keys.forEach(defaults.removeObject(forKey:))
            levels.forEach { defaults.removeObject(forKey: "levels.stars.\($0)") }
        }
        reset()
        addTeardownBlock(reset)

        for (level, item) in zip(levels, try cases("starAwards")) {
            let total = try XCTUnwrap(item["totalSeconds"] as? Int)
            let elapsed = try XCTUnwrap(item["elapsedSeconds"] as? Double)
            let stars = LevelProgressService.shared.recordCompletion(
                level: level,
                didWin: true,
                timeRemaining: total - Int(elapsed.rounded(.down)),
                totalTime: total,
                failedTries: try XCTUnwrap(item["failedTries"] as? Int)
            )
            XCTAssertEqual(stars, item["stars"] as? Int, "\(item)")
        }
    }

    func testAnInvalidPickFallsBackToTheDefaultName() {
        let fallback = LeaderboardNames.defaultWords(uid: "u")
        XCTAssertEqual(LeaderboardNames.words(adjective: 32, animal: 0, uid: "u"), fallback)
        XCTAssertEqual(LeaderboardNames.words(adjective: 1, animal: nil, uid: "u"), fallback)
        XCTAssertEqual(
            LeaderboardNames.words(adjective: 1, animal: 2, uid: "u"),
            LeaderboardNameWords(adjective: 1, animal: 2)
        )
    }

    func testMalformedRowsAreDropped() {
        let rows = LeaderboardRow.ranked(payload: [
            "good": ["s": 5, "t": 1],
            "text": ["s": "5", "t": 1],
            "noTime": ["s": 5],
            "negative": ["s": -1, "t": 1],
            "notARow": "x"
        ])
        XCTAssertEqual(rows.map(\.uid), ["good"])
    }

    func testConfigFailsClosed() {
        let on: [String: Any] = ["ios": ["enabled": true, "minVersion": "4.6.0"]]
        XCTAssertTrue(LeaderboardConfig(payload: on).allows(appVersion: "4.6.0"))
        XCTAssertTrue(LeaderboardConfig(payload: on).allows(appVersion: "4.10.0"))
        XCTAssertFalse(LeaderboardConfig(payload: on).allows(appVersion: "4.5.1"))
        XCTAssertFalse(LeaderboardConfig(payload: on).allows(appVersion: "unknown"))
        XCTAssertFalse(LeaderboardConfig(payload: nil).allows(appVersion: "9.9.9"))
        XCTAssertFalse(LeaderboardConfig(payload: "on").allows(appVersion: "9.9.9"))
        XCTAssertFalse(
            LeaderboardConfig(payload: ["android": ["enabled": true, "minVersion": "1.0.0"]])
                .allows(appVersion: "9.9.9")
        )
        XCTAssertFalse(
            LeaderboardConfig(payload: ["ios": ["enabled": true, "minVersion": ""]])
                .allows(appVersion: "9.9.9")
        )
        XCTAssertFalse(
            LeaderboardConfig(payload: ["ios": ["enabled": false, "minVersion": "1.0.0"]])
                .allows(appVersion: "9.9.9")
        )
    }
}

@MainActor
private final class FakeLeaderboardBackend: LeaderboardBackend {
    var config: Any? = ["ios": ["enabled": true, "minVersion": "1.0.0"]]
    var rows: [LeaderboardBoard: [String: Any]] = [:]
    var failNextWrite = false
    var writes: [[LeaderboardWrite]] = []
    var configReads = 0
    var topReads = 0
    var rowReads = 0
    var deletes = 0

    func currentUID() async throws -> String { "me" }

    func readConfig() async throws -> Any? {
        configReads += 1
        return config
    }

    func readTop(_ board: LeaderboardBoard) async throws -> [String: Any] {
        topReads += 1
        return rows[board] ?? [:]
    }

    func readRow(_ board: LeaderboardBoard, uid: String) async throws -> Any? {
        rowReads += 1
        return rows[board]?[uid]
    }

    func write(_ writes: [LeaderboardWrite], uid: String) async throws {
        if failNextWrite {
            failNextWrite = false
            throw LeaderboardError.timedOut
        }
        self.writes.append(writes)
    }

    func deleteRows(uid: String) async throws {
        deletes += 1
    }
}

@MainActor
final class LeaderboardServiceTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "LeaderboardServiceTests"
    private var backend: FakeLeaderboardBackend!
    private var scores: [LeaderboardBoard: Int] = [:]
    private var date = Date(timeIntervalSince1970: 1_000_000)
    private var service: LeaderboardService!

    override func setUp() async throws {
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        backend = FakeLeaderboardBackend()
        scores = [.stars: 10, .streak: 0]
        date = Date(timeIntervalSince1970: 1_000_000)
        service = makeService()
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeService(appVersion: String = "4.6.0") -> LeaderboardService {
        LeaderboardService(
            defaults: defaults,
            backend: backend,
            now: { [unowned self] in self.date },
            appVersion: appVersion,
            localScore: { [unowned self] in self.scores[$0] ?? 0 }
        )
    }

    private var sentScores: [Int] { backend.writes.flatMap { $0 }.map(\.score) }

    func testNothingIsSentBeforeTheNotice() async {
        await service.sync()
        XCTAssertTrue(backend.writes.isEmpty)
        XCTAssertEqual(backend.configReads, 0)
    }

    func testAZeroScoreCreatesNoRow() async {
        service.acknowledgeNotice()
        await service.sync()
        XCTAssertEqual(backend.writes.flatMap { $0 }.map(\.board), [.stars])
    }

    func testAScoreIsSentOnceThenOnlyWhenItRisesAfterTheGap() async {
        service.acknowledgeNotice()
        await service.sync()
        XCTAssertEqual(sentScores, [10])

        date.addTimeInterval(LeaderboardLimits.minimumWriteGap)
        await service.sync()
        XCTAssertEqual(sentScores, [10], "An unchanged score isn't sent again")

        scores[.stars] = 11
        date.addTimeInterval(-1)
        await service.sync()
        XCTAssertEqual(sentScores, [10], "Too soon")

        date.addTimeInterval(1)
        await service.sync()
        XCTAssertEqual(sentScores, [10, 11])
    }

    func testAFailedWriteIsRetriedAfterTheGap() async {
        service.acknowledgeNotice()
        backend.failNextWrite = true
        await service.sync()
        XCTAssertTrue(backend.writes.isEmpty)

        await service.sync()
        XCTAssertTrue(backend.writes.isEmpty, "A retry still waits for the gap")

        date.addTimeInterval(LeaderboardLimits.minimumWriteGap)
        await service.sync()
        XCTAssertEqual(sentScores, [10])
    }

    func testNoNetworkIsUsedWhenNothingIsDue() async {
        service.acknowledgeNotice()
        scores[.stars] = 0
        await service.sync()
        XCTAssertEqual(backend.configReads, 0)
    }

    func testTheKillSwitchStopsWritesAndReads() async {
        service.acknowledgeNotice()
        backend.config = nil
        await service.sync()
        XCTAssertTrue(backend.writes.isEmpty)

        do {
            _ = try await service.load(.stars)
            XCTFail("Expected unavailable")
        } catch {
            XCTAssertEqual(error as? LeaderboardError, .unavailable)
        }
        XCTAssertEqual(backend.topReads, 0)
    }

    func testAnOlderAppVersionStaysOff() async {
        backend.config = ["ios": ["enabled": true, "minVersion": "4.6.0"]]
        service = makeService(appVersion: "4.5.1")
        service.acknowledgeNotice()
        await service.sync()
        XCTAssertTrue(backend.writes.isEmpty)
    }

    func testAReinstallStartsFromTheExistingRow() async throws {
        backend.rows[.stars] = ["me": ["s": 500, "t": 1, "a": 3, "b": 4]]
        service.acknowledgeNotice()

        await service.sync()
        XCTAssertTrue(backend.writes.isEmpty, "A lower score would be rejected")

        let snapshot = try await service.load(.stars)
        XCTAssertEqual(snapshot.ownScore, 500)
        XCTAssertEqual(snapshot.ownWords, LeaderboardNameWords(adjective: 3, animal: 4))

        scores[.stars] = 501
        await service.sync()
        XCTAssertEqual(backend.writes.last, [
            LeaderboardWrite(board: .stars, score: 501, words: LeaderboardNameWords(adjective: 3, animal: 4))
        ])
    }

    func testOpeningABoardAfterAReinstallShowsTheExistingScore() async throws {
        backend.rows[.stars] = ["me": ["s": 500, "t": 1]]
        scores[.stars] = 0
        let snapshot = try await service.load(.stars)
        XCTAssertEqual(snapshot.ownScore, 500)
    }

    func testTheOwnRowIsReadOncePerBoard() async {
        service.acknowledgeNotice()
        await service.sync()
        scores[.stars] = 11
        date.addTimeInterval(LeaderboardLimits.minimumWriteGap)
        await service.sync()
        XCTAssertEqual(backend.rowReads, 1)
    }

    func testPickingANameUpdatesRowsThatHaveAScore() async throws {
        scores[.streak] = 2
        service.acknowledgeNotice()
        try await service.pickName(adjective: 1, animal: 2)
        let words = LeaderboardNameWords(adjective: 1, animal: 2)
        XCTAssertEqual(backend.writes, [[
            LeaderboardWrite(board: .stars, score: 10, words: words),
            LeaderboardWrite(board: .streak, score: 2, words: words)
        ]])
        let snapshot = try await service.load(.streak)
        XCTAssertEqual(snapshot.ownWords, words)
    }

    func testAPickWithoutAScoreIsSentWithTheFirstScore() async throws {
        scores[.stars] = 0
        service.acknowledgeNotice()
        try await service.pickName(adjective: 1, animal: 2)
        XCTAssertTrue(backend.writes.isEmpty)

        scores[.stars] = 3
        await service.sync()
        XCTAssertEqual(backend.writes.last?.first?.words, LeaderboardNameWords(adjective: 1, animal: 2))
    }

    func testAnInvalidPickIsRefused() async {
        service.acknowledgeNotice()
        do {
            try await service.pickName(adjective: 32, animal: 0)
            XCTFail("Expected invalidName")
        } catch {
            XCTAssertEqual(error as? LeaderboardError, .invalidName)
        }
        XCTAssertTrue(backend.writes.isEmpty)
    }

    func testLeavingDeletesRowsAndStopsWrites() async throws {
        service.acknowledgeNotice()
        await service.sync()
        try await service.leave()
        XCTAssertEqual(backend.deletes, 1)

        scores[.stars] = 20
        date.addTimeInterval(LeaderboardLimits.minimumWriteGap)
        await service.sync()
        XCTAssertEqual(sentScores, [10])
    }

    func testRejoiningSendsTheCurrentScore() async throws {
        service.acknowledgeNotice()
        await service.sync()
        try await service.leave()
        await service.rejoin()
        XCTAssertEqual(sentScores, [10, 10])
    }

    func testABoardIsCachedFor15Minutes() async throws {
        backend.rows[.stars] = ["a": ["s": 5, "t": 1]]
        _ = try await service.load(.stars)
        _ = try await service.load(.stars)
        XCTAssertEqual(backend.topReads, 1)
        XCTAssertEqual(backend.configReads, 2, "The kill switch is checked on each open")

        date.addTimeInterval(LeaderboardLimits.cacheSeconds)
        _ = try await service.load(.stars)
        XCTAssertEqual(backend.topReads, 2)
    }

    func testSnapshotReportsDistanceToTheBoard() async throws {
        var payload: [String: Any] = [:]
        for index in 0..<50 {
            payload["player\(index)"] = ["s": 100 + index, "t": 1]
        }
        backend.rows[.stars] = payload
        let snapshot = try await service.load(.stars)
        XCTAssertFalse(snapshot.isOwnRowOnBoard)
        XCTAssertEqual(snapshot.rows.first?.score, 149)
        XCTAssertEqual(snapshot.pointsToTopBoard, 91)
    }
}
