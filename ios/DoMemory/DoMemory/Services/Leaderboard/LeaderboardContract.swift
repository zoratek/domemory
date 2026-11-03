//
//  LeaderboardContract.swift
//  DoMemory
//
//  The pure rules both apps must agree on, because iOS and Android players read
//  and write the same rows: android/DOMEMORY_ANDROID_SPEC.md section 22.
//  firebase/fixtures/leaderboard-v1.json pins the expected values.
//

import Foundation

enum LeaderboardBoard: String, CaseIterable {
    case stars
    case streak

    var path: String { "leaderboard/v1/\(rawValue)" }
}

enum LeaderboardLimits {
    static let boardSize = 50
    static let cacheSeconds: TimeInterval = 15 * 60
    static let minimumWriteGap: TimeInterval = 10 * 60
}

struct LeaderboardNameWords: Equatable {
    let adjective: Int
    let animal: Int
}

enum LeaderboardNames {
    /// Frozen: translate these, but never reorder, replace or add to them, because
    /// that would rename players.
    static let adjectives = [
        "Swift", "Calm", "Brave", "Quiet", "Bright", "Clever", "Gentle", "Happy",
        "Kind", "Lucky", "Merry", "Mighty", "Noble", "Playful", "Proud", "Sunny",
        "Bold", "Cheerful", "Curious", "Daring", "Eager", "Friendly", "Golden", "Jolly",
        "Keen", "Lively", "Patient", "Silver", "Steady", "Tiny", "Wise", "Witty"
    ]

    /// Frozen, like `adjectives`.
    static let animals = [
        "Otter", "Panda", "Heron", "Fox", "Owl", "Koala", "Dolphin", "Tiger",
        "Rabbit", "Turtle", "Penguin", "Falcon", "Badger", "Beaver", "Deer", "Eagle",
        "Giraffe", "Hedgehog", "Kangaroo", "Lemur", "Lion", "Llama", "Moose", "Narwhal",
        "Parrot", "Puffin", "Raccoon", "Seal", "Sloth", "Swan", "Whale", "Zebra"
    ]

    static func defaultWords(uid: String) -> LeaderboardNameWords {
        let value = fnv1a64("leaderboard-name-" + uid)
        return LeaderboardNameWords(
            adjective: Int(value % UInt64(adjectives.count)),
            animal: Int((value >> 32) % UInt64(animals.count))
        )
    }

    /// The picked words when both are valid, otherwise the default name.
    static func words(adjective: Int?, animal: Int?, uid: String) -> LeaderboardNameWords {
        guard let adjective, let animal, isValid(adjective: adjective, animal: animal) else {
            return defaultWords(uid: uid)
        }
        return LeaderboardNameWords(adjective: adjective, animal: animal)
    }

    static func isValid(adjective: Int, animal: Int) -> Bool {
        adjectives.indices.contains(adjective) && animals.indices.contains(animal)
    }

    /// Standard FNV-1a 64. `SeededGenerator` can't be used here: its basis is one
    /// digit short of this one, so its numbers differ from Android's.
    static func fnv1a64(_ text: String) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return hash
    }
}

struct LeaderboardRow: Equatable, Identifiable {
    let uid: String
    let score: Int
    let updatedAt: Int
    let adjective: Int?
    let animal: Int?

    var id: String { uid }
    var nameWords: LeaderboardNameWords {
        LeaderboardNames.words(adjective: adjective, animal: animal, uid: uid)
    }

    init(uid: String, score: Int, updatedAt: Int, adjective: Int? = nil, animal: Int? = nil) {
        self.uid = uid
        self.score = score
        self.updatedAt = updatedAt
        self.adjective = adjective
        self.animal = animal
    }

    /// Nil for a row without a usable score or timestamp.
    init?(uid: String, value: Any?) {
        guard let fields = value as? [String: Any],
              let score = fields["s"] as? Int, score >= 0,
              let updatedAt = fields["t"] as? Int else { return nil }
        self.init(
            uid: uid,
            score: score,
            updatedAt: updatedAt,
            adjective: fields["a"] as? Int,
            animal: fields["b"] as? Int
        )
    }

    /// Highest score first, then whoever reached it earlier, then uid, so every
    /// client shows the same order.
    static func ranked(_ rows: [LeaderboardRow]) -> [LeaderboardRow] {
        rows.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt < rhs.updatedAt }
            return lhs.uid < rhs.uid
        }
    }

    static func ranked(payload: [String: Any]) -> [LeaderboardRow] {
        ranked(payload.compactMap { LeaderboardRow(uid: $0.key, value: $0.value) })
    }

    /// Points needed to pass the last row, or 0 while the board still has room.
    static func pointsToTopBoard(boardSize: Int, lastRowScore: Int, ownScore: Int) -> Int {
        guard boardSize >= LeaderboardLimits.boardSize else { return 0 }
        return max(0, lastRowScore - ownScore + 1)
    }
}

/// `/config/leaderboard`. Anything missing or malformed means off.
struct LeaderboardConfig: Equatable {
    let isEnabled: Bool
    let minimumVersion: String

    init(payload: Any?) {
        let platform = (payload as? [String: Any])?["ios"] as? [String: Any]
        isEnabled = platform?["enabled"] as? Bool ?? false
        minimumVersion = platform?["minVersion"] as? String ?? ""
    }

    func allows(appVersion: String) -> Bool {
        guard isEnabled,
              let minimum = Self.versionParts(minimumVersion),
              let current = Self.versionParts(appVersion) else { return false }
        return !current.lexicographicallyPrecedes(minimum)
    }

    private static func versionParts(_ version: String) -> [Int]? {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard parts.count == 3, !parts.contains(where: { $0 == nil }) else { return nil }
        return parts.compactMap { $0 }
    }
}
