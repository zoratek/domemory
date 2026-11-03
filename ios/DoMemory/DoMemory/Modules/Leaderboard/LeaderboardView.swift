//
//  LeaderboardView.swift
//  DoMemory
//

import SwiftUI

struct LeaderboardView: View {
    @State private var viewModel = LeaderboardViewModel()
    @State private var showNamePicker = false
    @State private var showLeaveConfirmation = false

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    if !viewModel.hasAcknowledgedNotice {
                        LeaderboardNoticeCard(
                            name: viewModel.ownName,
                            onAccept: { Task { await viewModel.acceptNotice() } },
                            onDecline: { viewModel.declineNotice() }
                        )
                    }

                    HStack(spacing: 8) {
                        Picker(Strings.leaderboardTitle, selection: boardSelection) {
                            Text(Strings.leaderboardTabStars).tag(LeaderboardBoard.stars)
                            Text(Strings.leaderboardTabStreak).tag(LeaderboardBoard.streak)
                        }
                        .pickerStyle(.segmented)

                        // The menu hides its navigation bar, so a toolbar item wouldn't show in a tab.
                        if viewModel.isParticipating {
                            optionsMenu
                        }
                    }

                    content
                }
                .padding(16)
                .readableWidth()
            }
        }
        .task {
            AnalyticsService.log(.leaderboardOpened)
            AnalyticsService.log(.screenView(name: "leaderboard", screenClass: "LeaderboardView"))
            await viewModel.open()
        }
        .sheet(isPresented: $showNamePicker) {
            LeaderboardNamePicker(words: viewModel.currentWords) { adjective, animal in
                await viewModel.pickName(adjective: adjective, animal: animal)
            }
        }
        .confirmationDialog(
            Strings.leaderboardLeaveConfirmTitle,
            isPresented: $showLeaveConfirmation,
            titleVisibility: .visible
        ) {
            Button(Strings.leaderboardLeave, role: .destructive) {
                Task { await viewModel.leave() }
            }
            Button(Strings.cancel, role: .cancel) {}
        } message: {
            Text(Strings.leaderboardLeaveConfirmMessage)
        }
        .alert(
            viewModel.errorMessage ?? "",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button(Strings.ok, role: .cancel) {}
        }
    }

    private var optionsMenu: some View {
        Menu {
            Button(Strings.leaderboardChangeName, systemImage: "pencil") {
                HapticsService.shared.fire(.tap)
                showNamePicker = true
            }
            Button(Strings.leaderboardLeave, systemImage: "person.fill.xmark", role: .destructive) {
                HapticsService.shared.fire(.tap)
                showLeaveConfirmation = true
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(Color.primaryColor)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityLabel(Strings.leaderboardOptionsAccessibility)
        }
        .disabled(viewModel.isWorking || !viewModel.isLoaded)
    }

    private var boardSelection: Binding<LeaderboardBoard> {
        Binding(
            get: { viewModel.board },
            set: { board in
                HapticsService.shared.fire(.select)
                Task { await viewModel.select(board) }
            }
        )
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.content {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
        case .unavailable:
            message(Strings.leaderboardUnavailable)
        case .failed:
            VStack(spacing: 12) {
                message(Strings.leaderboardFailed)
                Button(Strings.leaderboardRetry) {
                    Task { await viewModel.load() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.primaryColor)
            }
        case .loaded(let snapshot):
            loaded(snapshot)
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .medium, design: .rounded))
            .foregroundStyle(Color.textMuted)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
    }

    private func loaded(_ snapshot: LeaderboardSnapshot) -> some View {
        VStack(spacing: 16) {
            if viewModel.isParticipating {
                ownSummary(snapshot)
            } else if viewModel.hasAcknowledgedNotice {
                rejoinCard
            }

            if snapshot.rows.isEmpty {
                message(Strings.leaderboardEmpty)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(snapshot.rows.enumerated()), id: \.element.id) { index, row in
                        LeaderboardRowView(
                            rank: index + 1,
                            name: viewModel.name(for: row),
                            score: row.score,
                            board: snapshot.board,
                            isOwn: row.uid == snapshot.uid
                        )
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.surfacePrimary)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.surfaceBorder, lineWidth: 1))
                )
            }
        }
    }

    private func ownSummary(_ snapshot: LeaderboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(Strings.leaderboardYou(viewModel.ownName))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                LeaderboardScore(score: snapshot.ownScore, board: snapshot.board)
            }
            if snapshot.pointsToTopBoard > 0 {
                Text(snapshot.board == .stars
                     ? Strings.leaderboardPointsToTopStars(snapshot.pointsToTopBoard)
                     : Strings.leaderboardPointsToTopStreak(snapshot.pointsToTopBoard))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.textMuted)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.hardAmber.opacity(0.15))
        )
    }

    private var rejoinCard: some View {
        VStack(spacing: 8) {
            Text(Strings.leaderboardLeftMessage)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(Color.textMuted)
                .multilineTextAlignment(.center)
            Button(Strings.leaderboardJoinAgain) {
                HapticsService.shared.fire(.tap)
                Task { await viewModel.rejoin() }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.primaryColor)
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .disabled(viewModel.isWorking)
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.surfacePrimary)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.surfaceBorder, lineWidth: 1))
        )
    }
}

private struct LeaderboardRowView: View {
    let rank: Int
    let name: String
    let score: Int
    let board: LeaderboardBoard
    let isOwn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(rank <= 3 ? Color.hardAmber : Color.textMuted)
                .frame(minWidth: 28, alignment: .leading)
            Text(name)
                .font(.system(size: 15, weight: isOwn ? .bold : .medium, design: .rounded))
                .foregroundStyle(Color.textPrimary)
            Spacer(minLength: 8)
            LeaderboardScore(score: score, board: board)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(isOwn ? Color.hardAmber.opacity(0.15) : Color.clear)
        .accessibilityElement(children: .combine)
    }
}

private struct LeaderboardScore: View {
    let score: Int
    let board: LeaderboardBoard

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: board == .stars ? "star.fill" : "flame.fill")
                .font(.system(size: 13))
                .foregroundStyle(Color.hardAmber)
                .accessibilityLabel(board == .stars ? Strings.leaderboardTabStars : Strings.leaderboardTabStreak)
            Text("\(score)")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
        }
    }
}

/// The one-time notice shown before a player's first score is sent.
struct LeaderboardNoticeCard: View {
    let name: String
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Strings.leaderboardNoticeTitle)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(Color.textPrimary)
            Text(Strings.leaderboardNoticeBody(name))
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(Color.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button(Strings.leaderboardNoticeAccept) {
                    HapticsService.shared.fire(.tap)
                    onAccept()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.primaryColor)

                Button(Strings.leaderboardNoticeDecline) {
                    HapticsService.shared.fire(.tap)
                    onDecline()
                }
                .foregroundStyle(Color.textMuted)
            }
            .font(.system(size: 14, weight: .semibold, design: .rounded))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.surfacePrimary)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.surfaceBorder, lineWidth: 1))
        )
    }
}

private struct LeaderboardNamePicker: View {
    @Environment(\.dismiss) private var dismiss
    @State private var adjective: Int
    @State private var animal: Int
    @State private var isSaving = false
    private let formatter = LeaderboardNameFormatter.current
    let onSave: (Int, Int) async -> Bool

    init(words: LeaderboardNameWords, onSave: @escaping (Int, Int) async -> Bool) {
        _adjective = State(initialValue: words.adjective)
        _animal = State(initialValue: words.animal)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(formatter.name(LeaderboardNameWords(adjective: adjective, animal: animal)))
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .frame(maxWidth: .infinity)
                }
                Picker(Strings.leaderboardNameAdjective, selection: $adjective) {
                    ForEach(LeaderboardNames.adjectives.indices, id: \.self) { index in
                        Text(formatter.adjective(index, agreeingWith: animal)).tag(index)
                    }
                }
                Picker(Strings.leaderboardNameAnimal, selection: $animal) {
                    ForEach(LeaderboardNames.animals.indices, id: \.self) { index in
                        Text(formatter.animal(index)).tag(index)
                    }
                }
            }
            .navigationTitle(Strings.leaderboardNameTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Strings.leaderboardNameSave) {
                        isSaving = true
                        Task {
                            let saved = await onSave(adjective, animal)
                            isSaving = false
                            if saved { dismiss() }
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }
}
