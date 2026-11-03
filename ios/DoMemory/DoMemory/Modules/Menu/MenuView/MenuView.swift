//
//  MenuView.swift
//  DoMemory
//
//  Created by Ezequiel Barreto on 23/09/20.
//

import SwiftUI
import WaterfallGrid
import AppTrackingTransparency
import UserNotifications

/// The raw value is the `tab` parameter of `menu_tab_selected`.
private enum GameTab: String { case all, mine, levels, leaderboard }

struct MenuView: View {
    @State private var viewModel = MenuViewModel()
    @State var showNewView = false
    @State var showBanner = false
    @State private var showCreateSheet = false
    @State private var showJoinMultiplayerSheet = false
    @State private var isHostingMultiplayerRoom = false
    @State private var selectedTab: GameTab = .levels
    /// Stays false until the kill switch says the leaderboard is on for this version.
    @State private var isLeaderboardAvailable = false
    /// Set when the app, not the player, moves the tab, so that switch is not
    /// logged as `menu_tab_selected`.
    @State private var isProgrammaticTabChange = false
    @State private var randomMemorama: Memorama?
    @State private var dailyChallengeBoard: Memorama?
    @State private var statsRefreshID = UUID()
    @State private var purchaseService = PurchaseService.shared
    @State private var seasonCatalog = SeasonCatalogService.shared
    @State private var seasonDestination: Season?
    @ObservedObject private var deepLinkRouter = DeepLinkRouter.shared
    @State private var joinDeepLink: JoinDeepLink?
    @State private var showNotificationPrimer = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var displayedGames: [Memorama] {
        switch selectedTab {
        case .all:    return allGames
        case .mine:   return myGames
        case .levels, .leaderboard: return []
        }
    }

    private var allGames: [Memorama] {
        viewModel.memoramaArray.filter { !$0.id.hasPrefix("custom_") }
    }

    private var myGames: [Memorama] {
        viewModel.memoramaArray.filter { $0.id.hasPrefix("custom_") }
    }

    private var multiplayerAvailableGames: [Memorama] {
        viewModel.multiplayerCatalog
    }

    var body: some View {
        Group {
            if viewModel.isLoading {
                ZStack {
                    Color.appBackground.ignoresSafeArea()
                    LoadingView().padding()
                }
            } else {
                NavigationStack {
                    ZStack {
                        Color.appBackground.ignoresSafeArea()

                        VStack(spacing: 0) {
                            // Header
                            HStack {
                                Text(Strings.appName)
                                    .font(.righteous(size: 30))
                                    .foregroundStyle(Color.primaryColor)

                                Spacer()

                                Menu {
                                    Button {
                                        HapticsService.shared.fire(.tap)
                                        AnalyticsService.log(.multiplayerEntryTapped(action: "host"))
                                        isHostingMultiplayerRoom = true
                                    } label: {
                                        Label(Strings.multiplayerCreateRoom, systemImage: "person.2.badge.plus")
                                    }

                                    Button {
                                        HapticsService.shared.fire(.tap)
                                        AnalyticsService.log(.multiplayerEntryTapped(action: "join"))
                                        showJoinMultiplayerSheet = true
                                    } label: {
                                        Label(Strings.multiplayerJoinRoom, systemImage: "arrow.right.circle")
                                    }
                                } label: {
                                    Image(systemName: "person.2.fill")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(Color.primaryColor)
                                        .frame(width: 38, height: 38)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(Color.surfacePrimary)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                        .stroke(Color.surfaceBorder, lineWidth: 1)
                                                )
                                                .shadow(color: Color.shadowColor, radius: 6, x: 0, y: 3)
                                        )
                                }
                                .accessibilityLabel(Strings.multiplayerTitle)

                                Button(action: { HapticsService.shared.fire(.tap); openCreateSheet(source: "menu_header") }) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(Color.primaryColor)
                                        .frame(width: 38, height: 38)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(Color.surfacePrimary)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                        .stroke(Color.surfaceBorder, lineWidth: 1)
                                                )
                                                .shadow(color: Color.shadowColor, radius: 6, x: 0, y: 3)
                                        )
                                }
                                .buttonStyle(.plain)

                                Button(action: { HapticsService.shared.fire(.tap); self.showNewView = true }) {
                                    Image(systemName: "gearshape.fill")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(Color.textPrimary.opacity(0.6))
                                        .frame(width: 38, height: 38)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(Color.surfacePrimary)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                        .stroke(Color.surfaceBorder, lineWidth: 1)
                                                )
                                                .shadow(color: Color.shadowColor, radius: 6, x: 0, y: 3)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                            .padding(.bottom, 8)

                            // Daily challenge, sharing the row with the active
                            // season when there is one. With no season — the
                            // common case, and every failure mode of the
                            // catalog fetch — the daily card keeps the
                            // full-width layout it has always had.
                            if let season = seasonCatalog.activeSeason {
                                HStack(spacing: 12) {
                                    CompactDailyChallengeCard(
                                        streak: DailyChallengeService.shared.currentStreak,
                                        isCompleted: DailyChallengeService.shared.isCompletedToday(),
                                        onPlay: { openDailyChallenge(source: "card") }
                                    )

                                    SeasonCard(
                                        season: season,
                                        onOpen: {
                                            HapticsService.shared.fire(.tap)
                                            AnalyticsService.log(.seasonCardTapped(seasonID: season.id))
                                            seasonDestination = season
                                        }
                                    )
                                }
                                .id(statsRefreshID)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 8)
                            } else {
                                DailyChallengeCard(
                                    streak: DailyChallengeService.shared.currentStreak,
                                    isCompleted: DailyChallengeService.shared.isCompletedToday(),
                                    onPlay: { openDailyChallenge(source: "card") }
                                )
                                .id(statsRefreshID)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 8)
                            }

                            // The Android All tab makes the active catalog difficulty directly
                            // selectable. Keep iOS at the same entry point instead of exposing a
                            // read-only badge that sends players to Settings to change it.
                            if selectedTab == .all {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(Strings.difficulty)
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundStyle(Color.textMuted)

                                    MenuDifficultyPicker(selectedDifficulty: viewModel.selectedDifficulty) { difficulty in
                                        HapticsService.shared.fire(.select)
                                        viewModel.setDifficulty(difficulty)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.bottom, 8)
                            }

                            if !displayedGames.isEmpty {
                                Button {
                                    HapticsService.shared.fire(.tap)
                                    randomMemorama = viewModel.randomGame(for: selectedVisibleTab)
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "shuffle")
                                            .font(.system(size: 15, weight: .bold))
                                        Text(Strings.menuRandomGame)
                                            .font(.system(size: 16, weight: .bold, design: .rounded))
                                    }
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .fill(Color.primaryColor)
                                            .shadow(color: Color.primaryColor.opacity(0.25), radius: 12, x: 0, y: 4)
                                    )
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 12)
                            }

                            // The leaderboard is ad-free by decision.
                            if selectedTab != .leaderboard,
                               !purchaseService.hasRemovedAds,
                               AdsService.shared.isBannerConfigured(for: .homeBanner) {
                                AdMobBannerView(placement: .homeBanner)
                                    .frame(height: 50)
                                    .padding(.bottom, 8)
                            }

                            // Tab bar with per-tab content
                            TabView(selection: $selectedTab) {
                                LevelsView()
                                    .adFreeDayEntryPoint(source: "menu_levels")
                                    .tabItem {
                                        Label(Strings.tabLevels, systemImage: "trophy.fill")
                                    }
                                    .tag(GameTab.levels)

                                gamesTabContent(for: .mine, games: myGames)
                                    .adFreeDayEntryPoint(source: "menu_mine")
                                    .tabItem {
                                        Label(Strings.tabMine, systemImage: "square.and.pencil")
                                    }
                                    .tag(GameTab.mine)

                                gamesTabContent(for: .all, games: allGames)
                                    .adFreeDayEntryPoint(source: "menu_all")
                                    .tabItem {
                                        Label(Strings.tabAll, systemImage: "square.grid.2x2.fill")
                                    }
                                    .tag(GameTab.all)

                                if isLeaderboardAvailable {
                                    LeaderboardView()
                                        .tabItem {
                                            Label(Strings.leaderboardTitle, systemImage: "medal.fill")
                                        }
                                        .tag(GameTab.leaderboard)
                                }
                            }
                            .task {
                                isLeaderboardAvailable = await LeaderboardService.shared.checkAvailability()
                            }
                        }
                    }
                    .navigationBarHidden(true)
                    .navigationDestination(isPresented: $showNewView) {
                        SettingsView(listener: viewModel)
                    }
                    .navigationDestination(item: $randomMemorama) { memorama in
                        MemorizeView(
                            viewModel: MemorizeViewModel(memorama: memorama),
                            gameStartSource: "random_menu_button"
                        )
                        .onDisappear {
                            statsRefreshID = UUID()
                        }
                    }
                    .navigationDestination(item: $dailyChallengeBoard) { memorama in
                        MemorizeView(
                            viewModel: MemorizeViewModel(memorama: memorama, isDailyChallenge: true),
                            gameStartSource: "daily_challenge"
                        )
                        .onDisappear {
                            statsRefreshID = UUID()
                        }
                    }
                    .navigationDestination(item: $seasonDestination) { season in
                        SeasonLevelsView(season: season)
                            .onDisappear {
                                statsRefreshID = UUID()
                            }
                    }
                    .navigationDestination(item: $joinDeepLink) { link in
                        MultiplayerRoomView(entryMode: .join(link.code))
                    }
                    .navigationDestination(isPresented: $isHostingMultiplayerRoom) {
                        MultiplayerRoomView(
                            entryMode: .host,
                            availableMemoramas: multiplayerAvailableGames,
                            defaultDifficulty: viewModel.selectedDifficulty
                        )
                    }
                    .sheet(isPresented: $showCreateSheet) {
                        CreateMemoramaView(
                            currentDifficulty: viewModel.currentDifficulty,
                            onSave: { memorama in
                                viewModel.addCustomMemorama(memorama)
                                showMyMemoramas()
                            }
                        )
                    }
                    .sheet(isPresented: $showJoinMultiplayerSheet) {
                        JoinMultiplayerRoomView()
                    }
                }
            }
        }
        .task {
            if UIApplication.shared.applicationState != .active {
                for await _ in NotificationCenter.default
                    .notifications(named: UIApplication.didBecomeActiveNotification)
                    .prefix(1) {}
            }
            // Consent form first (EEA, UK and Switzerland only), then ATT, as
            // Google orders them. Mobile Ads starts after both, and only once
            // consent allows ad requests.
            await ConsentService.shared.gatherConsent()
            if ATTrackingManager.trackingAuthorizationStatus == .notDetermined {
                await ATTrackingManager.requestTrackingAuthorization()
            }
            await AdsService.shared.startIfAllowed()
            await presentNotificationPrimerIfNeeded()
        }
        .sheet(isPresented: $showNotificationPrimer) {
            NotificationPrimerView(source: "menu") {
                showNotificationPrimer = false
            }
        }
        // The primer's own system alert lands on `didBecomeActive`, which is
        // what triggers the app-open ad — same collision the What's New sheet has.
        .onChange(of: showNotificationPrimer) { _, isShowing in
            AdsService.shared.setFullScreenAdsSuppressed(isShowing)
        }
        // The player's tab switches. The Levels default on launch is not logged,
        // nor is the jump to "My memoramas" after creating one.
        .onChange(of: selectedTab) { previous, tab in
            if isProgrammaticTabChange {
                isProgrammaticTabChange = false
                return
            }
            AnalyticsService.log(.menuTabSelected(tab: tab.rawValue, previousTab: previous.rawValue))
        }
        .onAppear {
            statsRefreshID = UUID()
            AdsService.shared.registerMenuReadyForAppOpenAds()
            AnalyticsService.log(.screenView(name: "menu", screenClass: "MenuView"))
            // The cached catalog was already read synchronously when the
            // service was first touched, so a cache hit is on screen before
            // this call; the fetch only ever corrects it. Every failure —
            // no cache, no network, a kill switch off — leaves `activeSeason`
            // nil and the daily card full width.
            seasonCatalog.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            AdsService.shared.presentAppOpenAdIfAvailable()
            NotificationService.shared.refreshStreakAtRiskReminder()
            // A season's window is evaluated in wall-clock days, so an app left
            // open across local midnight would otherwise show a season that
            // ended yesterday.
            seasonCatalog.refreshActiveSeason()
        }
        .onReceive(deepLinkRouter.$pendingJoinCode.compactMap { $0 }) { code in
            joinDeepLink = JoinDeepLink(code: code)
            deepLinkRouter.pendingJoinCode = nil
        }
        .onReceive(deepLinkRouter.$shouldOpenDailyChallenge.filter { $0 }) { _ in
            if !DailyChallengeService.shared.isCompletedToday() {
                openDailyChallenge(source: "widget")
            }
            deepLinkRouter.shouldOpenDailyChallenge = false
        }
        .onReceive(deepLinkRouter.$pendingSeasonLink.compactMap { $0 }) { _ in
            // `$pendingSeasonLink` publishes in `willSet`, before the link is
            // stored: read here, the property still holds the old value, and a
            // nil written here is overwritten by the store. Route the link once
            // the assignment has finished.
            Task { @MainActor in openPendingSeasonLink() }
        }
        // On a first launch the season link can arrive before the catalog has
        // an active season; the request waits for it (briefly, see
        // `SeasonDeepLink.maxWait`).
        .onChange(of: seasonCatalog.activeSeason?.id) {
            openPendingSeasonLink()
        }
    }

    /// Opens the season a `domemory://season/<id>` link asked for, if it is the
    /// active one. A link for any other season leaves the player on the menu.
    private func openPendingSeasonLink() {
        guard let link = deepLinkRouter.pendingSeasonLink else { return }
        switch link.resolve(activeSeason: seasonCatalog.activeSeason) {
        case .open(let season):
            deepLinkRouter.pendingSeasonLink = nil
            seasonDestination = season
        case .wait:
            break
        case .drop:
            deepLinkRouter.pendingSeasonLink = nil
        }
    }

    /// Shows "My memoramas" after the player creates one, so the new board is on
    /// screen when the sheet closes (tracker #161; Android does the same).
    private func showMyMemoramas() {
        guard selectedTab != .mine else { return }
        isProgrammaticTabChange = true
        selectedTab = .mine
    }

    private func openCreateSheet(source: String) {
        AnalyticsService.log(.customMemoramaCreateOpened(source: source))
        showCreateSheet = true
    }

    /// `source` is `card` or `widget` (the `domemory://daily` deep link, or its
    /// https form). The completed card is disabled and the link is ignored once
    /// today is done, so every call is a real entry into today's challenge.
    private func openDailyChallenge(source: String) {
        AnalyticsService.log(
            .dailyChallengeOpened(source: source, streak: DailyChallengeService.shared.currentStreak)
        )
        dailyChallengeBoard = DailyChallengeService.shared.boardForToday()
    }

    private struct JoinDeepLink: Identifiable, Hashable {
        let id = UUID()
        let code: String
    }

    /// Shows the reminder primer once per install, and only while iOS would
    /// still accept an authorization request.
    ///
    /// Runs last in the launch sequence so it never stacks on the ATT alert.
    /// The flag is set before presenting: a user who dismisses the primer has
    /// spent their one uninvited ask, and can still enable reminders in Settings.
    private func presentNotificationPrimerIfNeeded() async {
        guard !UserDefaults.standard.bool(forKey: UserDefaultsKeys.notificationPrimerShown) else { return }

        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }

        UserDefaults.standard.set(true, forKey: UserDefaultsKeys.notificationPrimerShown)
        AnalyticsService.log(.notificationPrimerShown(source: "menu"))
        showNotificationPrimer = true
    }

    /// Two cards a row on iPhone. A regular-width iPad window fits one more
    /// column for roughly every 220pt, from three in a half-screen Split View
    /// up to five on a landscape 13-inch screen, so the cards stay card-sized.
    /// Read from the enclosing geometry rather than measured into state, so
    /// the grid's first frame already has the right column count instead of
    /// springing from three to five once a measurement lands.
    private func boardGridColumns(forWidth width: CGFloat) -> Int {
        guard horizontalSizeClass == .regular else { return 2 }
        return min(5, max(3, Int(width / 220)))
    }

    private var selectedVisibleTab: MenuViewModel.VisibleTab {
        switch selectedTab {
        case .all, .levels, .leaderboard:
            return .all
        case .mine:
            return .mine
        }
    }

    @ViewBuilder
    private func gamesTabContent(for tab: GameTab, games: [Memorama]) -> some View {
        if games.isEmpty && tab == .mine {
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "plus.square.dashed")
                    .font(.system(size: 52))
                    .foregroundStyle(Color.primaryColor.opacity(0.4))
                Text(Strings.emptyMyGames)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.textMuted)
                    .multilineTextAlignment(.center)
                Button(action: { HapticsService.shared.fire(.tap); openCreateSheet(source: "mine_empty_state") }) {
                    Text(Strings.emptyMyGamesAction)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(
                            Capsule().fill(Color.primaryColor)
                        )
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
        } else {
            GeometryReader { geo in
                ScrollView {
                    WaterfallGrid(games) { (memorama: Memorama) in
                        MemoramaGridCell(
                            memorama: memorama,
                            stats: viewModel.stats(for: memorama.id),
                            isFavorite: viewModel.isFavorite(id: memorama.id),
                            onStatsChanged: { statsRefreshID = UUID() },
                            onToggleFavorite: { viewModel.toggleFavorite(id: memorama.id) },
                            onDelete: memorama.id.hasPrefix("custom_")
                                ? { viewModel.deleteCustomMemorama(id: memorama.id) }
                                : nil
                        )
                    }
                    .gridStyle(
                        columns: boardGridColumns(forWidth: geo.size.width),
                        spacing: 14,
                        animation: Animation.spring(response: 0.35, dampingFraction: 0.85)
                    )
                    .id(statsRefreshID)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }
            .background(Color.appBackground)
        }
    }
}

private struct MemoramaGridCell: View {
    let memorama: Memorama
    let stats: GameStats
    let isFavorite: Bool
    let onStatsChanged: () -> Void
    let onToggleFavorite: () -> Void
    let onDelete: (() -> Void)?

    @State private var isNavigating = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button {
                HapticsService.shared.fire(.tap)
                isNavigating = true
            } label: {
                MemoramaCard(memorama: memorama, stats: stats)
            }
            .buttonStyle(.plain)
            .navigationDestination(isPresented: $isNavigating) {
                MemorizeView(
                    viewModel: MemorizeViewModel(memorama: memorama),
                    gameStartSource: "menu_card"
                )
                    .onDisappear(perform: onStatsChanged)
            }
            // Delete is the only remaining context-menu action, and it only
            // applies to custom memoramas. Attaching `.contextMenu` only
            // when there is an action avoids presenting an empty long-press
            // menu on every catalog card now that "Create room" is gone.
            .modifier(DeleteContextMenu(onDelete: onDelete))

            // A single, properly sized action on the card face: the favorite
            // toggle. Its previous 31pt frame sat well under Apple's 44pt
            // minimum tap target; it now gets a real 44pt hit area with a
            // visible tinted circle so the state (and the button itself) is
            // easy to see and to hit. Multiplayer moved off the card
            // entirely — starting a room no longer starts from a specific
            // game at all; the top bar's "host a room" button opens an empty
            // room and the game is picked inside the lobby instead.
            Button(action: { HapticsService.shared.fire(.tap); onToggleFavorite() }) {
                ZStack {
                    Circle()
                        .fill(isFavorite ? Color.secundaryColor.opacity(0.12) : Color.surfaceSecondary)
                        .frame(width: 36, height: 36)
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(isFavorite ? Color.secundaryColor : Color.textMuted)
                }
                .frame(width: 44, height: 44)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isFavorite ? Strings.menuFavoriteRemove : Strings.menuFavoriteAdd)
            .padding(.top, 4)
        }
    }
}

/// Attaches `.contextMenu` only when there is an action to show. A `nil`
/// `onDelete` (every catalog board) skips the modifier entirely rather than
/// presenting a context menu with zero items.
private struct DeleteContextMenu: ViewModifier {
    let onDelete: (() -> Void)?

    func body(content: Content) -> some View {
        if let onDelete {
            content.contextMenu {
                Button(role: .destructive, action: onDelete) {
                    Label(Strings.delete, systemImage: "trash")
                }
            }
        } else {
            content
        }
    }
}

/// The half-width layout used when a season shares the row.
///
/// A vertical stack of icon, title and badge rather than the full-width card's
/// horizontal one, which squeezes its 48pt circle, two lines of text and a
/// streak badge into roughly 170pt. Every element is a fixed height so this and
/// `SeasonCard` line up without either having to stretch.
private struct CompactCardLayout<Badge: View>: View {
    let glyph: AnyView
    let title: String
    let background: Color
    let badge: Badge
    /// Firebase-supplied artwork drawn over `background`. Declared last and
    /// defaulted so a card without artwork is unchanged.
    var artworkURL: URL? = nil
    /// Asset-catalog artwork drawn over `background`, for cards whose art ships
    /// in the bundle instead of arriving from Firebase. A season's art cannot be
    /// bundled — it is authored per season, after the build — and the daily
    /// challenge's is fixed, so the two are never both set.
    var artworkName: String? = nil

    private var hasArtwork: Bool { artworkURL != nil || artworkName != nil }

    @ViewBuilder
    private var artwork: some View {
        if let artworkURL {
            RemoteImage(url: artworkURL) { Color.clear }
                .scaledToFill()
        } else if let artworkName {
            Image(artworkName)
                .resizable()
                .scaledToFill()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 40, height: 40)
                glyph
            }

            Text(title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            badge
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.white.opacity(0.2)))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background {
            ZStack {
                background

                if hasArtwork {
                    // `Color.clear` takes exactly the card's size and an
                    // overlay cannot grow its parent, so the filled artwork
                    // crops to the card instead of stretching the ZStack — and
                    // with it the rounded corners and the shadow below.
                    Color.clear
                        .overlay { artwork }
                        .clipped()

                    // The title and badge are pure white at 15pt and 12pt with
                    // no shadow behind them, and the art is authored outside
                    // this file. This keeps the reading side of the card close
                    // to the flat accent it used to be while the artwork stays
                    // legible on the trailing edge.
                    LinearGradient(
                        colors: [background.opacity(0.85), background.opacity(0.25)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
            }
            // Clipped first, so the artwork takes the card's corner radius;
            // shadowed after, so the glow still falls outside it.
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: background.opacity(0.3), radius: 12, x: 0, y: 4)
            // Decoration only, for the reason spelled out on `DailyChallengeCard`.
            // The overflow is a few points here rather than ninety, because this
            // card's proportions nearly match the art's, but it is the same bug.
            .allowsHitTesting(false)
            // Decoration to VoiceOver too. `Image(_:)` built from an asset
            // name carries that name as its accessibility label, and this
            // layout is a button's content, so the label would be read out
            // after the title and badge — untranslated, in all ten locales.
            .accessibilityHidden(true)
        }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// The daily challenge's bundled card artwork, shared by the full-width and the
/// compact card so the two layouts cannot drift onto different images.
private let dailyChallengeArtworkName = "daily-challenge-card"

private struct CompactDailyChallengeCard: View {
    let streak: Int
    let isCompleted: Bool
    let onPlay: () -> Void

    private var badgeText: String {
        if streak > 0 { return Strings.dailyChallengeStreak(streak) }
        return isCompleted ? Strings.dailyChallengeCompleted : Strings.dailyChallengeSubtitle
    }

    var body: some View {
        Button(action: { if !isCompleted { HapticsService.shared.fire(.tap); onPlay() } }) {
            CompactCardLayout(
                glyph: AnyView(
                    Image(systemName: isCompleted ? "checkmark" : "calendar")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                ),
                title: Strings.dailyChallengeTitle,
                background: Color.primaryColor,
                badge: Text(badgeText),
                artworkName: dailyChallengeArtworkName
            )
            .opacity(isCompleted ? 0.85 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isCompleted)
    }
}

private struct SeasonCard: View {
    let season: Season
    let onOpen: () -> Void

    /// Derived from `season` on every evaluation rather than seeded into
    /// `@State`, because a season *handover* — `refreshActiveSeason()` crossing
    /// local midnight into the next season, or `load()` correcting a stale
    /// cache to a different one — rebuilds this card in the same structural
    /// position, which does not re-run a `State` initializer. Seeded state
    /// would then read the outgoing season's store under the incoming season's
    /// title and `levelCount`. The service holds no state of its own (every
    /// read hits `UserDefaults` live) and is trivial to construct, so there is
    /// nothing to cache.
    private var progress: SeasonProgressService { SeasonProgressService(season: season) }

    private var badgeText: String {
        let progress = self.progress
        guard !progress.isComplete(levelCount: season.levelCount) else {
            return Strings.seasonCompleteBadge
        }
        return Strings.seasonProgressFormat(
            progress.clearedLevelCount(levelCount: season.levelCount),
            season.levelCount
        )
    }

    var body: some View {
        Button(action: onOpen) {
            CompactCardLayout(
                glyph: AnyView(
                    Text(season.displayIcon)
                        .font(.system(size: 20))
                ),
                title: season.displayTitle,
                background: season.accent,
                badge: Text(badgeText),
                artworkURL: season.cardArtworkURL
            )
        }
        .buttonStyle(.plain)
    }
}

private struct DailyChallengeCard: View {
    let streak: Int
    let isCompleted: Bool
    let onPlay: () -> Void

    var body: some View {
        Button(action: { if !isCompleted { HapticsService.shared.fire(.tap); onPlay() } }) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 48, height: 48)
                    Image(systemName: isCompleted ? "checkmark" : "calendar")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(Strings.dailyChallengeTitle)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(isCompleted ? Strings.dailyChallengeCompleted : Strings.dailyChallengeSubtitle)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                }

                Spacer()

                if streak > 0 {
                    Text(Strings.dailyChallengeStreak(streak))
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.white.opacity(0.2)))
                } else if !isCompleted {
                    Image(systemName: "play.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background {
                ZStack {
                    Color.primaryColor

                    // Sized the same way as `CompactCardLayout`: `Color.clear`
                    // fixes the frame so the filled artwork crops to the card
                    // rather than stretching it, and with it the corners below.
                    Color.clear
                        .overlay {
                            Image(dailyChallengeArtworkName)
                                .resizable()
                                .scaledToFill()
                        }
                        .clipped()

                    // A heavier scrim than the compact card's. This layout is
                    // roughly four times as wide as it is tall, so filling it
                    // from 4:3 art crops a narrow band from the middle and
                    // scales the motif up — and the title, subtitle and streak
                    // badge all sit on top of it in unshadowed white.
                    LinearGradient(
                        colors: [Color.primaryColor.opacity(0.92), Color.primaryColor.opacity(0.35)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
                // Clipped first, so the artwork takes the card's corner radius;
                // shadowed after, so the glow still falls outside it.
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: Color.primaryColor.opacity(0.3), radius: 12, x: 0, y: 4)
                // `clipped()` and `clipShape` only clip *drawing*. This card is
                // roughly four times as wide as it is tall, so filling it from
                // 4:3 art leaves the image about 90pt taller than the card at
                // each edge, and that overflow still answers touches — it sat
                // over the header buttons and opened the daily challenge
                // instead. The art is decoration; it takes no input.
                .allowsHitTesting(false)
                // And no accessibility label either, for the reason spelled
                // out on `CompactCardLayout`.
                .accessibilityHidden(true)
            }
            .opacity(isCompleted ? 0.85 : 1)
            // With the background inert, the tappable region is the card
            // itself rather than only the glyphs and text inside it.
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isCompleted)
    }
}

struct MemoramaCard: View {
    var memorama: Memorama
    var stats: GameStats

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.surfacePrimary)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.surfaceBorder, lineWidth: 1)
                )
                .shadow(color: Color.shadowColor, radius: 10, x: 0, y: 4)
                .frame(height: 156)

            VStack(spacing: 10) {
                // No name label: the catalog has no per-board names, so the
                // emoji alone carries identity here — stepped up from 44 to
                // 52pt to fill the space the label used to occupy.
                if let first = memorama.items.first {
                    Text(first)
                        .font(.system(size: 52))
                }

                HStack(spacing: 8) {
                    StatBadge(label: Strings.statsPlayed, value: stats.playedCount, color: Color.primaryColor)
                    StatBadge(label: Strings.statsWon, value: stats.wonCount, color: Color.easyGreen)
                }
            }
            .padding(12)
        }
        .padding(.vertical, 4)
    }
}

private struct StatBadge: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Text("\(value)")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(color)

            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.textMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(color.opacity(0.1))
        )
    }
}

// MARK: - Create Memorama Sheet

private struct CreateMemoramaView: View {
    let currentDifficulty: String
    let onSave: (Memorama) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var items: [String] = []
    @State private var newEmoji: String = ""
    @State private var isAddingEmoji = false

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && items.count >= 2
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Name field
                        VStack(alignment: .leading, spacing: 8) {
                            Text(Strings.createName)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.textMuted)

                            TextField(
                                "",
                                text: $name,
                                prompt: Text(Strings.createNamePlaceholder)
                                    .foregroundStyle(Color.textMuted)
                            )
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.textPrimary)
                                .padding(14)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color.surfacePrimary)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .stroke(Color.surfaceBorder, lineWidth: 1)
                                        )
                                        .shadow(color: Color.shadowColor, radius: 6, x: 0, y: 2)
                                )
                        }

                        // Items section
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("\(Strings.createEmojisCount) (\(items.count))")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Color.textMuted)
                                Spacer()
                                Text(Strings.createMinimum)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.textMuted.opacity(0.6))
                            }

                            if !items.isEmpty {
                                VStack(spacing: 8) {
                                    ForEach(Array(items.enumerated()), id: \.offset) { index, emoji in
                                        HStack {
                                            Text(emoji)
                                                .font(.system(size: 36))
                                                .frame(width: 50)
                                            Text(emoji)
                                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                                .foregroundStyle(Color.textMuted)
                                            Spacer()
                                            Button {
                                                HapticsService.shared.fire(.tap)
                                                items.remove(at: index)
                                            } label: {
                                                Image(systemName: "minus.circle.fill")
                                                    .foregroundStyle(Color.secundaryColor.opacity(0.8))
                                                    .font(.system(size: 20))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 10)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(Color.surfacePrimary)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                        .stroke(Color.surfaceBorder, lineWidth: 1)
                                                )
                                        )
                                    }
                                }
                            }

                            if isAddingEmoji {
                                HStack(spacing: 10) {
                                    TextField(
                                        "",
                                        text: $newEmoji,
                                        prompt: Text("😀")
                                            .foregroundStyle(Color.textMuted)
                                    )
                                        .font(.system(size: 32))
                                        .foregroundStyle(Color.textPrimary)
                                        .frame(width: 50)
                                        .multilineTextAlignment(.center)
                                        .onChange(of: newEmoji) { _, value in
                                            if value.count > 1 {
                                                newEmoji = String(value.prefix(1))
                                            }
                                        }

                                    Button(Strings.createAdd) {
                                        let trimmed = String(newEmoji.prefix(1))
                                        guard !trimmed.isEmpty, !items.contains(trimmed) else { return }
                                        items.append(trimmed)
                                        newEmoji = ""
                                        isAddingEmoji = false
                                    }
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundStyle(newEmoji.isEmpty ? Color.textMuted : Color.primaryColor)
                                    .disabled(newEmoji.isEmpty)

                                    Button(Strings.cancel) {
                                        newEmoji = ""
                                        isAddingEmoji = false
                                    }
                                    .font(.system(size: 15, design: .rounded))
                                    .foregroundStyle(Color.textMuted)
                                }
                                .padding(14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color.surfacePrimary)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .strokeBorder(Color.surfaceBorder, lineWidth: 1)
                                        )
                                )
                            }

                            if !isAddingEmoji {
                                Button {
                                    HapticsService.shared.fire(.tap)
                                    isAddingEmoji = true
                                } label: {
                                    HStack {
                                        Image(systemName: "plus.circle.fill")
                                        Text(Strings.createAddEmoji)
                                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    }
                                    .foregroundStyle(Color.primaryColor)
                                    .padding(14)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(Color.primaryColor.opacity(0.12))
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle(Strings.createTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.cancel) { dismiss() }
                        .foregroundStyle(Color.textMuted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Strings.createSave) {
                        let memorama = Memorama(
                            id: "custom_" + UUID().uuidString,
                            name: name.trimmingCharacters(in: .whitespaces),
                            category: "custom",
                            difficulty: currentDifficulty,
                            description: "",
                            publishedDate: ISO8601DateFormatter().string(from: Date()),
                            items: items,
                            itemType: "string",
                            isDoubleItem: false
                        )
                        onSave(memorama)
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(canSave ? Color.primaryColor : Color.textMuted)
                    .disabled(!canSave)
                }
            }
        }
    }
}

#Preview {
    MenuView()
}
