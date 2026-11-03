//
//  FirebaseLeaderboardBackend.swift
//  DoMemory
//

import Foundation
import FirebaseAuth
import FirebaseCore
import FirebaseDatabase

struct LeaderboardWrite: Equatable {
    let board: LeaderboardBoard
    let score: Int
    let words: LeaderboardNameWords?
}

enum LeaderboardError: Error, Equatable {
    case unavailable
    case notParticipating
    case invalidName
    case timedOut
}

/// The seam between the leaderboard's rules and Firebase, so the rules can be
/// tested without a database.
@MainActor
protocol LeaderboardBackend {
    func currentUID() async throws -> String
    func readConfig() async throws -> Any?
    func readTop(_ board: LeaderboardBoard) async throws -> [String: Any]
    func readRow(_ board: LeaderboardBoard, uid: String) async throws -> Any?
    func write(_ writes: [LeaderboardWrite], uid: String) async throws
    func deleteRows(uid: String) async throws
}

@MainActor
struct FirebaseLeaderboardBackend: LeaderboardBackend {
    private static let timeoutSeconds: TimeInterval = 10

    func currentUID() async throws -> String {
        guard FirebaseApp.app() != nil else { throw LeaderboardError.unavailable }
        if let uid = Auth.auth().currentUser?.uid { return uid }
        return try await withCheckedThrowingContinuation { continuation in
            Auth.auth().signInAnonymously { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let uid = result?.user.uid {
                    continuation.resume(returning: uid)
                } else {
                    continuation.resume(throwing: LeaderboardError.unavailable)
                }
            }
        }
    }

    func readConfig() async throws -> Any? {
        guard FirebaseApp.app() != nil else { throw LeaderboardError.unavailable }
        _ = try await currentUID()
        return try await read(Database.database().reference().child("config/leaderboard"))
    }

    func readTop(_ board: LeaderboardBoard) async throws -> [String: Any] {
        let query = Database.database().reference().child(board.path)
            .queryOrdered(byChild: "s")
            .queryLimited(toLast: UInt(LeaderboardLimits.boardSize))
        return try await read(query) as? [String: Any] ?? [:]
    }

    func readRow(_ board: LeaderboardBoard, uid: String) async throws -> Any? {
        try await read(Database.database().reference().child(board.path).child(uid))
    }

    func write(_ writes: [LeaderboardWrite], uid: String) async throws {
        var values: [String: Any] = [:]
        for write in writes {
            var row: [String: Any] = ["s": write.score, "t": ServerValue.timestamp()]
            if let words = write.words {
                row["a"] = words.adjective
                row["b"] = words.animal
            }
            values["\(write.board.path)/\(uid)"] = row
        }
        try await update(values)
    }

    func deleteRows(uid: String) async throws {
        var values: [String: Any] = [:]
        for board in LeaderboardBoard.allCases {
            values["\(board.path)/\(uid)"] = NSNull()
        }
        try await update(values)
    }

    /// A single read. Without a time limit, it would wait indefinitely while offline.
    private func read(_ query: DatabaseQuery) async throws -> Any? {
        try await withTimeout { finish in
            query.observeSingleEvent(of: .value) { snapshot in
                finish(.success(LeaderboardValue(snapshot.value is NSNull ? nil : snapshot.value)))
            } withCancel: { error in
                finish(.failure(error))
            }
        }.value
    }

    private func update(_ values: [String: Any]) async throws {
        _ = try await withTimeout { finish in
            Database.database().reference().updateChildValues(values) { error, _ in
                if let error {
                    finish(.failure(error))
                } else {
                    finish(.success(LeaderboardValue(nil)))
                }
            }
        }
    }

    private func withTimeout(
        _ start: (@escaping (Result<LeaderboardValue, Error>) -> Void) -> Void
    ) async throws -> LeaderboardValue {
        try await withCheckedThrowingContinuation { continuation in
            var isFinished = false
            let finish: (Result<LeaderboardValue, Error>) -> Void = { result in
                DispatchQueue.main.async {
                    guard !isFinished else { return }
                    isFinished = true
                    continuation.resume(with: result)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.timeoutSeconds) {
                finish(.failure(LeaderboardError.timedOut))
            }
            start(finish)
        }
    }
}

/// Carries a decoded Firebase value through a continuation.
private struct LeaderboardValue: @unchecked Sendable {
    let value: Any?

    init(_ value: Any?) {
        self.value = value
    }
}
