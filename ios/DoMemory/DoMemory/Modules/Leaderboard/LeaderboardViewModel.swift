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
    private(set) var hasLeft: Bool
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
        hasLeft = service.hasLeft
    }

    var isParticipating: Bool { hasAcknowledgedNotice && !hasLeft }

    var isLoaded: Bool {
        if case .loaded = content { return true }
        return false
    }

    func name(for row: LeaderboardRow) -> String {
        formatter.name(row.nameWords)
    }

    func open() async {
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

    func acceptNotice() async {
        service.acknowledgeNotice()
        hasAcknowledgedNotice = true
        AnalyticsService.log(.leaderboardNoticeAnswered(accepted: true))
        await service.sync()
        await load()
    }

    func declineNotice() {
        service.declineNotice()
        hasAcknowledgedNotice = true
        hasLeft = true
        AnalyticsService.log(.leaderboardNoticeAnswered(accepted: false))
    }

    func leave() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await service.leave()
            hasLeft = true
            AnalyticsService.log(.leaderboardLeft)
            await load()
        } catch {
            errorMessage = Strings.leaderboardLeaveFailed
        }
    }

    func rejoin() async {
        isWorking = true
        defer { isWorking = false }
        await service.rejoin()
        hasAcknowledgedNotice = true
        hasLeft = false
        AnalyticsService.log(.leaderboardRejoined)
        await refreshName()
        await load()
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
