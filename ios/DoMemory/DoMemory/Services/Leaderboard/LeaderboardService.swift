//
//  LeaderboardService.swift
//  DoMemory
//
//  Sends the player's scores to the shared leaderboard and reads the top of each
//  board. Nothing is sent until the player has seen the one-time notice
//  (`acknowledgeNotice()`), and a failure here never affects the game.
//

import Foundation

struct LeaderboardSnapshot: Equatable {
    let board: LeaderboardBoard
    let rows: [LeaderboardRow]
    let uid: String
    let ownScore: Int
    let ownWords: LeaderboardNameWords

    var isOwnRowOnBoard: Bool { rows.contains { $0.uid == uid } }
    var pointsToTopBoard: Int {
        guard !isOwnRowOnBoard, let last = rows.last else { return 0 }
        return LeaderboardRow.pointsToTopBoard(
            boardSize: rows.count,
            lastRowScore: last.score,
            ownScore: ownScore
        )
    }
}

@MainActor
final class LeaderboardService {
    static let shared = LeaderboardService()

    private enum Key {
        static let noticeAcknowledged = "leaderboard.noticeAcknowledged"
        static let hasLeft = "leaderboard.hasLeft"
        static let adjective = "leaderboard.adjective"
        static let animal = "leaderboard.animal"
        static func lastSent(_ board: LeaderboardBoard) -> String { "leaderboard.\(board.rawValue).lastSent" }
        static func lastAttempt(_ board: LeaderboardBoard) -> String { "leaderboard.\(board.rawValue).lastAttempt" }
        static func reconciled(_ board: LeaderboardBoard) -> String { "leaderboard.\(board.rawValue).reconciled" }
    }

    private let defaults: UserDefaults
    private let backend: LeaderboardBackend
    private let now: () -> Date
    private let appVersion: String
    private let localScore: (LeaderboardBoard) -> Int

    private var cache: [LeaderboardBoard: (date: Date, rows: [LeaderboardRow])] = [:]
    private var isSyncing = false

    init(
        defaults: UserDefaults = .standard,
        backend: LeaderboardBackend? = nil,
        now: @escaping () -> Date = Date.init,
        appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
        localScore: @escaping (LeaderboardBoard) -> Int = { board in
            switch board {
            case .stars: return LevelProgressService.shared.totalStars
            case .streak: return DailyChallengeService.shared.longestStreak
            }
        }
    ) {
        self.defaults = defaults
        self.backend = backend ?? FirebaseLeaderboardBackend()
        self.now = now
        self.appVersion = appVersion
        self.localScore = localScore
    }

    // MARK: - Participation

    var hasAcknowledgedNotice: Bool { defaults.bool(forKey: Key.noticeAcknowledged) }
    var hasLeft: Bool { defaults.bool(forKey: Key.hasLeft) }
    var isParticipating: Bool { hasAcknowledgedNotice && !hasLeft }

    func acknowledgeNotice() {
        defaults.set(true, forKey: Key.noticeAcknowledged)
    }

    /// Deletes the player's rows and stops further writes until `rejoin()`.
    func leave() async throws {
        let uid = try await backend.currentUID()
        try await backend.deleteRows(uid: uid)
        defaults.set(true, forKey: Key.hasLeft)
        for board in LeaderboardBoard.allCases {
            defaults.removeObject(forKey: Key.lastSent(board))
            defaults.removeObject(forKey: Key.lastAttempt(board))
            defaults.removeObject(forKey: Key.reconciled(board))
        }
        cache.removeAll()
    }

    func rejoin() async {
        acknowledgeNotice()
        defaults.set(false, forKey: Key.hasLeft)
        await sync()
    }

    // MARK: - Sending scores

    /// Called after every finished game. Doesn't start any work unless a score is due.
    func syncAfterGame() {
        guard isParticipating, LeaderboardBoard.allCases.contains(where: isWriteDue) else { return }
        Task { await sync() }
    }

    /// Sends whichever scores are due. Failures are ignored, and a later game tries again.
    func sync() async {
        guard isParticipating, !isSyncing else { return }
        guard LeaderboardBoard.allCases.contains(where: isWriteDue) else { return }
        isSyncing = true
        defer { isSyncing = false }

        do {
            guard try await isAvailable() else { return }
            let uid = try await backend.currentUID()
            for board in LeaderboardBoard.allCases where isWriteDue(board) {
                try await reconcile(board, uid: uid)
                guard isWriteDue(board) else { continue }
                defaults.set(now().timeIntervalSince1970, forKey: Key.lastAttempt(board))
                let score = localScore(board)
                try await backend.write(
                    [LeaderboardWrite(board: board, score: score, words: pickedWords)],
                    uid: uid
                )
                defaults.set(score, forKey: Key.lastSent(board))
            }
        } catch {
            return
        }
    }

    /// Changes the player's name on any rows they have. Without one yet, the pick
    /// is sent with their first score.
    func pickName(adjective: Int, animal: Int) async throws {
        guard isParticipating else { throw LeaderboardError.notParticipating }
        guard LeaderboardNames.isValid(adjective: adjective, animal: animal) else {
            throw LeaderboardError.invalidName
        }
        guard try await isAvailable() else { throw LeaderboardError.unavailable }

        let uid = try await backend.currentUID()
        let words = LeaderboardNameWords(adjective: adjective, animal: animal)
        var writes: [LeaderboardWrite] = []
        for board in LeaderboardBoard.allCases {
            try await reconcile(board, uid: uid)
            let score = ownScore(board)
            if score > 0 {
                writes.append(LeaderboardWrite(board: board, score: score, words: words))
            }
        }
        if !writes.isEmpty {
            try await backend.write(writes, uid: uid)
            for write in writes {
                defaults.set(write.score, forKey: Key.lastSent(write.board))
                defaults.set(now().timeIntervalSince1970, forKey: Key.lastAttempt(write.board))
            }
        }
        defaults.set(adjective, forKey: Key.adjective)
        defaults.set(animal, forKey: Key.animal)
        cache.removeAll()
    }

    // MARK: - Reading

    /// The top of a board, kept for 15 minutes. Throws `unavailable` while the kill
    /// switch is off.
    func load(_ board: LeaderboardBoard) async throws -> LeaderboardSnapshot {
        guard try await isAvailable() else { throw LeaderboardError.unavailable }
        let uid = try await backend.currentUID()

        let rows: [LeaderboardRow]
        if let cached = cache[board], now().timeIntervalSince(cached.date) < LeaderboardLimits.cacheSeconds {
            rows = cached.rows
        } else {
            rows = LeaderboardRow.ranked(payload: try await backend.readTop(board))
            cache[board] = (now(), rows)
        }

        try await reconcile(board, uid: uid)
        return LeaderboardSnapshot(
            board: board,
            rows: rows,
            uid: uid,
            ownScore: ownScore(board),
            ownWords: pickedWords ?? LeaderboardNames.defaultWords(uid: uid)
        )
    }

    // MARK: - Helpers

    private func isAvailable() async throws -> Bool {
        LeaderboardConfig(payload: try await backend.readConfig()).allows(appVersion: appVersion)
    }

    private func isWriteDue(_ board: LeaderboardBoard) -> Bool {
        guard localScore(board) > defaults.integer(forKey: Key.lastSent(board)) else { return false }
        let lastAttempt = defaults.double(forKey: Key.lastAttempt(board))
        return now().timeIntervalSince1970 - lastAttempt >= LeaderboardLimits.minimumWriteGap
    }

    private func ownScore(_ board: LeaderboardBoard) -> Int {
        max(localScore(board), defaults.integer(forKey: Key.lastSent(board)))
    }

    private var pickedWords: LeaderboardNameWords? {
        guard defaults.object(forKey: Key.adjective) != nil,
              defaults.object(forKey: Key.animal) != nil else { return nil }
        let adjective = defaults.integer(forKey: Key.adjective)
        let animal = defaults.integer(forKey: Key.animal)
        guard LeaderboardNames.isValid(adjective: adjective, animal: animal) else { return nil }
        return LeaderboardNameWords(adjective: adjective, animal: animal)
    }

    /// A reinstall can keep the uid while local stats restart at zero, and rules
    /// reject a lower score, so the first read or write on an install starts from
    /// any existing row.
    private func reconcile(_ board: LeaderboardBoard, uid: String) async throws {
        guard !defaults.bool(forKey: Key.reconciled(board)) else { return }
        if let row = LeaderboardRow(uid: uid, value: try await backend.readRow(board, uid: uid)) {
            defaults.set(max(row.score, defaults.integer(forKey: Key.lastSent(board))), forKey: Key.lastSent(board))
            if pickedWords == nil, let adjective = row.adjective, let animal = row.animal,
               LeaderboardNames.isValid(adjective: adjective, animal: animal) {
                defaults.set(adjective, forKey: Key.adjective)
                defaults.set(animal, forKey: Key.animal)
            }
        }
        defaults.set(true, forKey: Key.reconciled(board))
    }
}
