//
//  LeaderboardViewModel.swift
//  DoMemory
//

import Foundation
import Observation

@MainActor
@Observable
final class LeaderboardViewModel {
    enum Content: Equatable {
        case loading
        case loaded(LeaderboardSnapshot)
        case unavailable
        case failed
    }

    private(set) var board: LeaderboardBoard = .stars
    private(set) var content: Content = .loading
    private(set) var hasAcknowledgedNotice: Bool
    private(set) var ownName = ""
    private(set) var isWorking = false
    var errorMessage: String?

    @ObservationIgnored private let service: LeaderboardService
    @ObservationIgnored private let formatter: LeaderboardNameFormatter

    init(service: LeaderboardService? = nil, formatter: LeaderboardNameFormatter = .current) {
        let service = service ?? .shared
        self.service = service
        self.formatter = formatter
        hasAcknowledgedNotice = service.hasAcknowledgedNotice
    }

    var isLoaded: Bool {
        if case .loaded = content { return true }
        return false
    }

    func name(for row: LeaderboardRow) -> String {
        formatter.name(row.nameWords)
    }

    func open() async {
        // The notice may have been answered on the Levels tab since this last appeared.
        hasAcknowledgedNotice = service.hasAcknowledgedNotice
        await refreshName()
        await service.sync()
        await load()
    }

    func select(_ board: LeaderboardBoard) async {
        guard board != self.board else { return }
        self.board = board
        AnalyticsService.log(.leaderboardBoardSelected(board: board.rawValue))
        await load()
    }

    func dismissNotice() {
        service.acknowledgeNotice()
        hasAcknowledgedNotice = true
        AnalyticsService.log(.leaderboardNoticeDismissed)
    }

    func load() async {
        content = .loading
        let requested = board
        do {
            let snapshot = try await service.load(requested)
            guard requested == board else { return }
            content = .loaded(snapshot)
        } catch LeaderboardError.unavailable {
            guard requested == board else { return }
            content = .unavailable
        } catch {
            guard requested == board else { return }
            content = .failed
        }
    }

    /// Returns true when the name was saved.
    func pickName(adjective: Int, animal: Int) async -> Bool {
        isWorking = true
        defer { isWorking = false }
        do {
            try await service.pickName(adjective: adjective, animal: animal)
            AnalyticsService.log(.leaderboardNameChanged)
            await refreshName()
            await load()
            return true
        } catch {
            errorMessage = Strings.leaderboardNameFailed
            return false
        }
    }

    var currentWords: LeaderboardNameWords {
        if case .loaded(let snapshot) = content { return snapshot.ownWords }
        return LeaderboardNameWords(adjective: 0, animal: 0)
    }

    private func refreshName() async {
        if let words = await service.ownNameWords() {
            ownName = formatter.name(words)
        }
    }
}
