//
//  LeaderboardView.swift
//  DoMemory
//

import SwiftUI

struct LeaderboardView: View {
    @State private var viewModel = LeaderboardViewModel()
    @State private var showNamePicker = false

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    if !viewModel.hasAcknowledgedNotice {
                        LeaderboardNoticeCard(
                            name: viewModel.ownName,
                            onDismiss: { viewModel.dismissNotice() }
                        )
                    }

                    Picker(Strings.leaderboardTitle, selection: boardSelection) {
                        Text(Strings.leaderboardTabStars).tag(LeaderboardBoard.stars)
                        Text(Strings.leaderboardTabStreak).tag(LeaderboardBoard.streak)
                    }
                    .pickerStyle(.segmented)

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
        VStack(alignment: .leading, spacing: 16) {
            Text(snapshot.board == .stars ? Strings.leaderboardCaptionStars : Strings.leaderboardCaptionStreak)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Color.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)

            LeaderboardTicket(
                snapshot: snapshot,
                name: viewModel.ownName,
                canChangeName: !viewModel.isWorking,
                onChangeName: {
                    HapticsService.shared.fire(.tap)
                    showNamePicker = true
                }
            )

            if snapshot.rows.isEmpty {
                message(Strings.leaderboardEmpty)
            } else {
                Text(Strings.leaderboardTop50)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                LazyVStack(spacing: 0) {
                    ForEach(Array(snapshot.rows.enumerated()), id: \.element.id) { index, row in
                        LeaderboardRowView(
                            rank: index + 1,
                            name: viewModel.name(for: row),
                            score: row.score,
                            board: snapshot.board,
                            isOwn: row.uid == snapshot.uid
                        )
                        if index < snapshot.rows.count - 1 {
                            Divider().overlay(Color.surfaceBorder)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.surfacePrimary)
                )
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.surfaceBorder, lineWidth: 1))
            }
        }
    }
}

/// The player's own score, the most personal thing on the screen.
private struct LeaderboardTicket: View {
    let snapshot: LeaderboardSnapshot
    let name: String
    let canChangeName: Bool
    let onChangeName: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) {
                    identity
                    Spacer(minLength: 8)
                    score
                }
                VStack(alignment: .leading, spacing: 8) {
                    identity
                    score
                }
            }
            .accessibilityElement(children: .combine)

            Line()
                .stroke(Color.surfaceBorder, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .frame(height: 1)
                .accessibilityHidden(true)

            Text(statusText)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onChangeName) {
                Label(Strings.leaderboardChangeName, systemImage: "pencil")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.primaryColor)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canChangeName)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 6)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.surfacePrimary)
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.primaryColor, lineWidth: 2))
        )
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Strings.leaderboardYou.uppercased())
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(Color.primaryColor)
            Text(name)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var score: some View {
        HStack(spacing: 6) {
            Image(systemName: snapshot.board == .stars ? "star.fill" : "flame.fill")
                .font(.system(size: 24))
                .foregroundStyle(Color.hardAmber)
                .accessibilityLabel(snapshot.board == .stars ? Strings.leaderboardTabStars : Strings.leaderboardTabStreak)
            Text("\(snapshot.ownScore)")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
        }
    }

    private var statusText: String {
        switch snapshot.ticketStatus {
        case .ranked(let rank):
            return Strings.leaderboardRank(rank)
        case .pointsToTopBoard(let points):
            return snapshot.board == .stars
                ? Strings.leaderboardPointsToTopStars(points)
                : Strings.leaderboardPointsToTopStreak(points)
        case .noScore:
            return snapshot.board == .stars ? Strings.leaderboardZeroStars : Strings.leaderboardZeroStreak
        case .pending:
            return Strings.leaderboardPending
        }
    }
}

private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

private struct LeaderboardRowView: View {
    let rank: Int
    let name: String
    let score: Int
    let board: LeaderboardBoard
    let isOwn: Bool

    private var medal: Color? {
        switch rank {
        case 1: return .medalGold
        case 2: return .medalSilver
        case 3: return .medalBronze
        default: return nil
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(medal == nil ? Color.textMuted : Color.onMedal)
                .frame(minWidth: 30, minHeight: 30)
                .background {
                    if let medal {
                        Circle().fill(medal)
                    }
                }
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 15, weight: isOwn ? .bold : .medium, design: .rounded))
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if isOwn {
                    Text(Strings.leaderboardYou)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.primaryColor)
                }
            }
            Spacer(minLength: 8)
            LeaderboardScore(score: score, board: board)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(isOwn ? Color.primaryColor.opacity(0.1) : Color.clear)
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

/// The one-time notice telling a player they're on the public leaderboard.
struct LeaderboardNoticeCard: View {
    let name: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Strings.leaderboardNoticeTitle)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(Color.textPrimary)
            Text(Strings.leaderboardNoticeBody(name))
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(Color.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            Button(Strings.leaderboardNoticeAccept) {
                HapticsService.shared.fire(.tap)
                onDismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.primaryColor)
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
