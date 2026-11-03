//
//  LeaderboardScreenTests.swift
//  DoMemoryTests
//

import XCTest
@testable import DoMemory

final class LeaderboardNameFormatterTests: XCTestCase {
    private static let locales = ["en", "es-419", "de", "fr", "hi", "it", "ja", "ko", "pt-BR", "zh-Hans"]

    private var languages: [String: LeaderboardNameFormatter.Language] {
        LeaderboardNameFormatter.loadLanguages(bundle: Bundle(for: SeasonProgressService.self))
    }

    func testEveryLocaleHasEveryWord() throws {
        for code in Self.locales {
            let language = try XCTUnwrap(languages[code], code)
            XCTAssertEqual(language.adjectives.count, LeaderboardNames.adjectives.count, code)
            XCTAssertEqual(language.animals.count, LeaderboardNames.animals.count, code)
            XCTAssertTrue(language.format.contains("{adjective}"), code)
            XCTAssertTrue(language.format.contains("{animal}"), code)
            XCTAssertFalse(language.adjectives.contains { $0.isEmpty || $0.contains("") }, code)
            XCTAssertFalse(language.animals.contains { $0.word.isEmpty }, code)
            XCTAssertTrue(language.animals.allSatisfy { ["m", "f", "n"].contains($0.gender) }, code)
        }
    }

    func testEnglishWordsMatchTheFrozenLists() throws {
        let english = try XCTUnwrap(languages["en"])
        XCTAssertEqual(english.adjectives.compactMap(\.first), LeaderboardNames.adjectives)
        XCTAssertEqual(english.animals.map(\.word), LeaderboardNames.animals)
    }

    func testEnglishNameUsesTheAdjectiveFirst() throws {
        let formatter = LeaderboardNameFormatter(language: languages["en"])
        XCTAssertEqual(formatter.name(LeaderboardNameWords(adjective: 0, animal: 0)), "Swift Otter")
    }

    func testAdjectivesAgreeWithTheAnimal() throws {
        let spanish = LeaderboardNameFormatter(language: languages["es-419"])
        // Calm + Otter (feminine) and Calm + Panda (masculine).
        XCTAssertEqual(spanish.name(LeaderboardNameWords(adjective: 1, animal: 0)), "Nutria Tranquila")
        XCTAssertEqual(spanish.name(LeaderboardNameWords(adjective: 1, animal: 1)), "Panda Tranquilo")

        let german = LeaderboardNameFormatter(language: languages["de"])
        // Brave + Otter (m), Owl (f) and Kangaroo (n).
        XCTAssertEqual(german.name(LeaderboardNameWords(adjective: 2, animal: 0)), "Mutiger Otter")
        XCTAssertEqual(german.name(LeaderboardNameWords(adjective: 2, animal: 4)), "Mutige Eule")
        XCTAssertEqual(german.name(LeaderboardNameWords(adjective: 2, animal: 18)), "Mutiges Känguru")
        // Merry and Cheerful, whose stems end in -er.
        XCTAssertEqual(german.name(LeaderboardNameWords(adjective: 10, animal: 20)), "Heiterer Löwe")
        XCTAssertEqual(german.name(LeaderboardNameWords(adjective: 17, animal: 30)), "Munterer Wal")
    }

    func testAMissingLanguageFallsBackToEnglish() {
        let formatter = LeaderboardNameFormatter(language: nil)
        XCTAssertEqual(formatter.name(LeaderboardNameWords(adjective: 0, animal: 0)), "Swift Otter")
    }
}

@MainActor
private final class ScreenBackend: LeaderboardBackend {
    var config: Any? = ["ios": ["enabled": true, "minVersion": "1.0.0"]]
    var rows: [String: Any] = [:]
    var configReads = 0
    var writes = 0
    var failWrites = false
    var failTopReads = false

    func currentUID() async throws -> String { "me" }
    func readConfig() async throws -> Any? {
        configReads += 1
        return config
    }
    func readTop(_ board: LeaderboardBoard) async throws -> [String: Any] {
        if failTopReads { throw LeaderboardError.timedOut }
        return rows
    }
    func readRow(_ board: LeaderboardBoard, uid: String) async throws -> Any? { nil }
    func write(_ writes: [LeaderboardWrite], uid: String) async throws {
        if failWrites { throw LeaderboardError.timedOut }
        self.writes += 1
    }
}

@MainActor
final class LeaderboardViewModelTests: XCTestCase {
    private let suiteName = "LeaderboardViewModelTests"
    private var defaults: UserDefaults!
    private var backend: ScreenBackend!
    private var service: LeaderboardService!
    private var viewModel: LeaderboardViewModel!

    override func setUp() async throws {
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        backend = ScreenBackend()
        service = LeaderboardService(
            defaults: defaults,
            backend: backend,
            appVersion: "4.6.0",
            localScore: { $0 == .stars ? 10 : 0 }
        )
        viewModel = LeaderboardViewModel(service: service, formatter: LeaderboardNameFormatter(language: nil))
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testOpeningSendsTheScoreAndLoadsTheBoard() async {
        backend.rows = ["a": ["s": 5, "t": 1]]
        await viewModel.open()
        XCTAssertEqual(backend.writes, 1)
        guard case .loaded(let snapshot) = viewModel.content else {
            return XCTFail("Expected a loaded board")
        }
        XCTAssertEqual(snapshot.rows.map(\.uid), ["a"])
    }

    func testDismissingTheNoticeRemembersIt() async {
        XCTAssertFalse(viewModel.hasAcknowledgedNotice)
        viewModel.dismissNotice()
        XCTAssertTrue(viewModel.hasAcknowledgedNotice)
        XCTAssertTrue(service.hasAcknowledgedNotice)
    }

    func testTheKillSwitchShowsTheUnavailableState() async {
        backend.config = nil
        await viewModel.open()
        XCTAssertEqual(viewModel.content, .unavailable)
    }

    func testAFailedReadShowsTheRetryStateAndRecovers() async {
        backend.failTopReads = true
        await viewModel.load()
        XCTAssertEqual(viewModel.content, .failed)

        backend.failTopReads = false
        await viewModel.load()
        guard case .loaded = viewModel.content else { return XCTFail("Expected a loaded board") }
    }

    func testPickingANameRefreshesTheName() async {
        let saved = await viewModel.pickName(adjective: 0, animal: 0)
        XCTAssertTrue(saved)
        XCTAssertEqual(viewModel.ownName, "Swift Otter")
    }

    func testAFailedPickReportsIt() async {
        backend.failWrites = true
        let saved = await viewModel.pickName(adjective: 0, animal: 0)
        XCTAssertFalse(saved)
        XCTAssertEqual(viewModel.errorMessage, Strings.leaderboardNameFailed)
    }

    func testAvailabilityIsCheckedOncePerLaunch() async {
        let first = await service.checkAvailability()
        let second = await service.checkAvailability()
        XCTAssertTrue(first)
        XCTAssertTrue(second)
        XCTAssertEqual(backend.configReads, 1)
    }

    func testAvailabilityFailsClosed() async {
        backend.config = ["ios": ["enabled": false, "minVersion": "1.0.0"]]
        let available = await service.checkAvailability()
        XCTAssertFalse(available)
    }
}
