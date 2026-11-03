//
//  AppConfiguration.swift
//  DoMemory
//
//  Created by Ezequiel Barreto on 23/09/20.
//

import SwiftUI
import FirebaseAnalytics

enum AppConfiguration {
    static let unitGame = "e362a87fcadb4afb"
    static let unitHome = "a9ee7d214e9f5dab"
}

enum AnalyticsEvent {
    case screenView(name: String, screenClass: String)
    case difficultySelected(difficulty: String)
    case menuLoaded(difficulty: String)
    /// The player switched menu tab: `levels`, `mine` or `all`.
    case menuTabSelected(tab: String, previousTab: String)
    case gameListLoaded(difficulty: String, gameCount: Int, customCount: Int)
    case gameStarted(source: String, difficulty: String, cardsCount: Int, isCustom: Bool)
    case gameFinished(result: String, difficulty: String, cardsCount: Int, failedTries: Int, timeRemaining: Int, isCustom: Bool)
    case cardTapped(difficulty: String, cardsCount: Int, failedTries: Int)
    case pauseOpened(difficulty: String, timeRemaining: Int)
    case resumeTapped(difficulty: String, timeRemaining: Int)
    case quitConfirmed(difficulty: String, timeRemaining: Int, failedTries: Int)
    case retryTapped(difficulty: String, cardsCount: Int, source: String)
    case favoriteToggled(gameID: String, isFavorite: Bool)
    /// The create-memorama sheet was opened: `menu_header` (the + button) or
    /// `mine_empty_state`. Compare with `customMemoramaCreated` for the share
    /// of players who finish building one.
    case customMemoramaCreateOpened(source: String)
    case customMemoramaCreated(gameID: String, difficulty: String, cardsCount: Int)
    case customMemoramaDeleted(gameID: String)
    /// A choice in the menu's multiplayer menu: `host` or `join`. Precedes
    /// `multiplayerRoomCreated` / `multiplayerRoomJoined`, which only fire once
    /// the backend accepts, so the gap between the two is abandonment.
    case multiplayerEntryTapped(action: String)
    case multiplayerRoomCreated(gameID: String, isCustom: Bool)
    case multiplayerRoomJoined
    case multiplayerGameStarted(gameID: String)
    case multiplayerGameFinished(result: String)
    case adLifecycle(placement: String, action: String)
    case whatsNewShown(version: String)
    case whatsNewDismissed(version: String)
    case whatsNewOpenedFromSettings(version: String)
    case notificationPrimerShown(source: String)
    case notificationPrimerCompleted(source: String, outcome: String)
    case reviewLinkOpened(source: String)
    /// The player entered today's challenge: `card` (the menu card) or
    /// `widget` (the widget's `daily` deep link). Once per entry, unlike
    /// `dailyChallengeStarted`, which fires again on every retry.
    case dailyChallengeOpened(source: String, streak: Int)
    case dailyChallengeStarted(streak: Int)
    case dailyChallengeFinished(result: String, streak: Int)
    case streakMilestone(days: Int)
    case multiplayerInviteSent(source: String)
    case multiplayerInviteOpened
    case resultShared(source: String)
    case onboardingIntroCompleted
    case onboardingIntroSkipped
    case achievementsOpened(source: String)
    case leaderboardOpened
    case leaderboardBoardSelected(board: String)
    case leaderboardNoticeDismissed
    case leaderboardNameChanged
    /// Only logged when the pick differs from the current theme. Values are
    /// `AppTheme` raw values: `system`, `light`, `dark`.
    case themeChanged(theme: String, previousTheme: String)
    // Season play reuses the numbered-level events rather than getting a
    // parallel set, so the season and endless-Levels funnels stay directly
    // comparable. `seasonID` is nil for endless Levels and the key is then
    // omitted entirely, leaving those events exactly the shape they were.
    case levelStarted(level: Int, seasonID: String? = nil)
    /// `powerUpsUsed` counts star power-ups bought during this attempt, so the
    /// share of level plays that used any is one filter away.
    case levelFinished(level: Int, result: String, stars: Int, powerUpsUsed: Int, seasonID: String? = nil)
    case levelUnlocked(level: Int, seasonID: String? = nil)
    case levelLifeConsumed(livesRemaining: Int)
    /// A loss just spent the day's last life. `levelOutOfLivesShown` only
    /// fires later, when the player taps a level with none left.
    case levelLivesDepleted(level: Int, seasonID: String? = nil)
    case levelLifeGrantedFromAd(livesRemaining: Int)
    case levelOutOfLivesShown(source: String)
    case levelStarsCredited(level: Int, amount: Int, balanceAfter: Int, seasonID: String? = nil)
    case levelPowerUpUsed(powerUp: String, level: Int, cost: Int, balanceAfter: Int, seasonID: String? = nil)
    case levelLifePurchasedWithStars(cost: Int, balanceAfter: Int)
    case levelSkipped(level: Int, cost: Int, balanceAfter: Int)
    case levelFailedByMistakes(level: Int, maxFailures: Int, timeRemaining: Int)
    case levelMistakesForgiven(level: Int, amount: Int, source: String)
    case levelsIntroShown(source: String)
    case levelsIntroCompleted
    /// `slidesSeen` is how far the player got before skipping (1-based).
    case levelsIntroSkipped(slidesSeen: Int)
    /// The active season's card on the menu was tapped. Once per tap, unlike
    /// `seasonLevelsEntered`, which also fires on returning from a level.
    case seasonCardTapped(seasonID: String)
    /// Fired every time a season's level map appears, including returning to
    /// it from a level — distinct from the generic `screenView`, which
    /// carries no season identity. Lets a season's entry funnel be filtered
    /// on its own in Firebase.
    case seasonLevelsEntered(seasonID: String)
    // The ad-free day offer, in funnel order: entry tapped → offer shown →
    // watch tapped → ad watched (once per ad) → granted. The rewarded ad's
    // load and dismissal are still tracked through `adLifecycle` under the
    // `ad_free_day_rewarded` placement; these carry the ad's place in the
    // chain, which `adLifecycle` cannot.
    /// The "No Ads" pill or the Settings row was tapped. `state` is what the
    /// entry point showed: `idle`, `in_progress` (one ad done) or `active`.
    case adFreeDayEntryTapped(source: String, state: String, adsWatched: Int)
    case adFreeDayOfferShown(source: String, isIntro: Bool, adsWatched: Int)
    /// The sheet's "Watch ad N of 2" button was tapped with an ad ready.
    case adFreeDayWatchTapped(source: String, adNumber: Int)
    /// Rewarded ad N of the chain paid out. The last one is always followed
    /// by `adFreeDayGranted`.
    case adFreeDayAdWatched(source: String, adNumber: Int)
    case adFreeDayGranted(source: String)

    var name: String {
        switch self {
        case .screenView: return AnalyticsEventScreenView
        case .difficultySelected: return "difficulty_selected"
        case .menuLoaded: return "menu_loaded"
        case .menuTabSelected: return "menu_tab_selected"
        case .gameListLoaded: return "game_list_loaded"
        case .gameStarted: return "game_started"
        case .gameFinished: return "game_finished"
        case .cardTapped: return "card_tapped"
        case .pauseOpened: return "pause_opened"
        case .resumeTapped: return "resume_tapped"
        case .quitConfirmed: return "quit_confirmed"
        case .retryTapped: return "retry_tapped"
        case .favoriteToggled: return "favorite_toggled"
        case .customMemoramaCreateOpened: return "custom_memorama_create_opened"
        case .customMemoramaCreated: return "custom_memorama_created"
        case .customMemoramaDeleted: return "custom_memorama_deleted"
        case .multiplayerEntryTapped: return "multiplayer_entry_tapped"
        case .multiplayerRoomCreated: return "multiplayer_room_created"
        case .multiplayerRoomJoined: return "multiplayer_room_joined"
        case .multiplayerGameStarted: return "multiplayer_game_started"
        case .multiplayerGameFinished: return "multiplayer_game_finished"
        case .adLifecycle: return "ad_lifecycle"
        case .whatsNewShown: return "whats_new_shown"
        case .whatsNewDismissed: return "whats_new_dismissed"
        case .whatsNewOpenedFromSettings: return "whats_new_opened_from_settings"
        case .notificationPrimerShown: return "notification_primer_shown"
        case .notificationPrimerCompleted: return "notification_primer_completed"
        case .reviewLinkOpened: return "review_link_opened"
        case .dailyChallengeOpened: return "daily_challenge_opened"
        case .dailyChallengeStarted: return "daily_challenge_started"
        case .dailyChallengeFinished: return "daily_challenge_finished"
        case .streakMilestone: return "streak_milestone"
        case .multiplayerInviteSent: return "multiplayer_invite_sent"
        case .multiplayerInviteOpened: return "multiplayer_invite_opened"
        case .resultShared: return "result_shared"
        case .onboardingIntroCompleted: return "onboarding_intro_completed"
        case .onboardingIntroSkipped: return "onboarding_intro_skipped"
        case .achievementsOpened: return "achievements_opened"
        case .leaderboardOpened: return "leaderboard_opened"
        case .leaderboardBoardSelected: return "leaderboard_board_selected"
        case .leaderboardNoticeDismissed: return "leaderboard_notice_dismissed"
        case .leaderboardNameChanged: return "leaderboard_name_changed"
        case .themeChanged: return "theme_changed"
        case .levelStarted: return "level_started"
        case .levelFinished: return "level_finished"
        case .levelUnlocked: return "level_unlocked"
        case .levelLifeConsumed: return "level_life_consumed"
        case .levelLivesDepleted: return "level_lives_depleted"
        case .levelLifeGrantedFromAd: return "level_life_granted_from_ad"
        case .levelOutOfLivesShown: return "level_out_of_lives_shown"
        case .levelStarsCredited: return "level_stars_credited"
        case .levelPowerUpUsed: return "level_power_up_used"
        case .levelLifePurchasedWithStars: return "level_life_purchased_with_stars"
        case .levelSkipped: return "level_skipped"
        case .levelFailedByMistakes: return "level_failed_by_mistakes"
        case .levelMistakesForgiven: return "level_mistakes_forgiven"
        case .levelsIntroShown: return "levels_intro_shown"
        case .levelsIntroCompleted: return "levels_intro_completed"
        case .levelsIntroSkipped: return "levels_intro_skipped"
        case .seasonCardTapped: return "season_card_tapped"
        case .seasonLevelsEntered: return "season_levels_entered"
        case .adFreeDayEntryTapped: return "ad_free_day_entry_tapped"
        case .adFreeDayOfferShown: return "ad_free_day_offer_shown"
        case .adFreeDayWatchTapped: return "ad_free_day_watch_tapped"
        case .adFreeDayAdWatched: return "ad_free_day_ad_watched"
        case .adFreeDayGranted: return "ad_free_day_granted"
        }
    }

    var parameters: [String: Any] {
        switch self {
        case .screenView(let name, let screenClass):
            return [
                AnalyticsParameterScreenName: name,
                AnalyticsParameterScreenClass: screenClass
            ]
        case .difficultySelected(let difficulty):
            return ["difficulty": difficulty]
        case .menuLoaded(let difficulty):
            return ["difficulty": difficulty]
        case .menuTabSelected(let tab, let previousTab):
            return [
                "tab": tab,
                "previous_tab": previousTab
            ]
        case .gameListLoaded(let difficulty, let gameCount, let customCount):
            return [
                "difficulty": difficulty,
                "game_count": gameCount,
                "custom_count": customCount
            ]
        case .gameStarted(let source, let difficulty, let cardsCount, let isCustom):
            return [
                "source": source,
                "difficulty": difficulty,
                "cards_count": cardsCount,
                "is_custom": isCustom ? 1 : 0
            ]
        case .gameFinished(let result, let difficulty, let cardsCount, let failedTries, let timeRemaining, let isCustom):
            return [
                "result": result,
                "difficulty": difficulty,
                "cards_count": cardsCount,
                "failed_tries": failedTries,
                "time_remaining": timeRemaining,
                "is_custom": isCustom ? 1 : 0
            ]
        case .cardTapped(let difficulty, let cardsCount, let failedTries):
            return [
                "difficulty": difficulty,
                "cards_count": cardsCount,
                "failed_tries": failedTries
            ]
        case .pauseOpened(let difficulty, let timeRemaining):
            return [
                "difficulty": difficulty,
                "time_remaining": timeRemaining
            ]
        case .resumeTapped(let difficulty, let timeRemaining):
            return [
                "difficulty": difficulty,
                "time_remaining": timeRemaining
            ]
        case .quitConfirmed(let difficulty, let timeRemaining, let failedTries):
            return [
                "difficulty": difficulty,
                "time_remaining": timeRemaining,
                "failed_tries": failedTries
            ]
        case .retryTapped(let difficulty, let cardsCount, let source):
            return [
                "difficulty": difficulty,
                "cards_count": cardsCount,
                "source": source
            ]
        case .favoriteToggled(let gameID, let isFavorite):
            return [
                "game_id": gameID,
                "is_favorite": isFavorite ? 1 : 0
            ]
        case .customMemoramaCreateOpened(let source):
            return ["source": source]
        case .customMemoramaCreated(let gameID, let difficulty, let cardsCount):
            return [
                "game_id": gameID,
                "difficulty": difficulty,
                "cards_count": cardsCount
            ]
        case .customMemoramaDeleted(let gameID):
            return ["game_id": gameID]
        case .multiplayerEntryTapped(let action):
            return ["action": action]
        case .multiplayerRoomCreated(let gameID, let isCustom):
            return [
                "game_id": gameID,
                "is_custom": isCustom ? 1 : 0
            ]
        case .multiplayerRoomJoined:
            return [:]
        case .multiplayerGameStarted(let gameID):
            return ["game_id": gameID]
        case .multiplayerGameFinished(let result):
            return ["result": result]
        case .adLifecycle(let placement, let action):
            return [
                "placement": placement,
                "action": action
            ]
        case .whatsNewShown(let version):
            return ["version": version]
        case .whatsNewDismissed(let version):
            return ["version": version]
        case .whatsNewOpenedFromSettings(let version):
            return ["version": version]
        case .notificationPrimerShown(let source):
            return ["source": source]
        case .notificationPrimerCompleted(let source, let outcome):
            return [
                "source": source,
                "outcome": outcome
            ]
        case .reviewLinkOpened(let source):
            return ["source": source]
        case .dailyChallengeOpened(let source, let streak):
            return [
                "source": source,
                "streak": streak
            ]
        case .dailyChallengeStarted(let streak):
            return ["streak": streak]
        case .dailyChallengeFinished(let result, let streak):
            return [
                "result": result,
                "streak": streak
            ]
        case .streakMilestone(let days):
            return ["days": days]
        case .multiplayerInviteSent(let source):
            return ["source": source]
        case .multiplayerInviteOpened:
            return [:]
        case .resultShared(let source):
            return ["source": source]
        case .onboardingIntroCompleted, .onboardingIntroSkipped:
            return [:]
        case .achievementsOpened(let source):
            return ["source": source]
        case .leaderboardOpened, .leaderboardNameChanged, .leaderboardNoticeDismissed:
            return [:]
        case .leaderboardBoardSelected(let board):
            return ["board": board]
        case .themeChanged(let theme, let previousTheme):
            return [
                "theme": theme,
                "previous_theme": previousTheme
            ]
        case .levelStarted(let level, let seasonID):
            return AnalyticsEvent.tagged(["level": level], seasonID: seasonID)
        case .levelFinished(let level, let result, let stars, let powerUpsUsed, let seasonID):
            return AnalyticsEvent.tagged(
                [
                    "level": level,
                    "result": result,
                    "stars": stars,
                    "power_ups_used": powerUpsUsed
                ],
                seasonID: seasonID
            )
        case .levelUnlocked(let level, let seasonID):
            return AnalyticsEvent.tagged(["level": level], seasonID: seasonID)
        case .levelLifeConsumed(let livesRemaining):
            return ["lives_remaining": livesRemaining]
        case .levelLivesDepleted(let level, let seasonID):
            return AnalyticsEvent.tagged(["level": level], seasonID: seasonID)
        case .levelLifeGrantedFromAd(let livesRemaining):
            return ["lives_remaining": livesRemaining]
        case .levelOutOfLivesShown(let source):
            return ["source": source]
        case .levelStarsCredited(let level, let amount, let balanceAfter, let seasonID):
            return AnalyticsEvent.tagged(
                [
                    "level": level,
                    "amount": amount,
                    "balance_after": balanceAfter
                ],
                seasonID: seasonID
            )
        case .levelPowerUpUsed(let powerUp, let level, let cost, let balanceAfter, let seasonID):
            return AnalyticsEvent.tagged(
                [
                    "power_up": powerUp,
                    "level": level,
                    "cost": cost,
                    "balance_after": balanceAfter
                ],
                seasonID: seasonID
            )
        case .levelLifePurchasedWithStars(let cost, let balanceAfter):
            return [
                "cost": cost,
                "balance_after": balanceAfter
            ]
        case .levelSkipped(let level, let cost, let balanceAfter):
            return [
                "level": level,
                "cost": cost,
                "balance_after": balanceAfter
            ]
        case .levelFailedByMistakes(let level, let maxFailures, let timeRemaining):
            return [
                "level": level,
                "max_failures": maxFailures,
                "time_remaining": timeRemaining
            ]
        case .levelMistakesForgiven(let level, let amount, let source):
            return [
                "level": level,
                "amount": amount,
                "source": source
            ]
        case .levelsIntroShown(let source):
            return ["source": source]
        case .levelsIntroCompleted:
            return [:]
        case .levelsIntroSkipped(let slidesSeen):
            return ["slides_seen": slidesSeen]
        case .seasonCardTapped(let seasonID):
            return ["season_id": seasonID]
        case .seasonLevelsEntered(let seasonID):
            return ["season_id": seasonID]
        case .adFreeDayEntryTapped(let source, let state, let adsWatched):
            return [
                "source": source,
                "state": state,
                "ads_watched": adsWatched
            ]
        case .adFreeDayWatchTapped(let source, let adNumber),
             .adFreeDayAdWatched(let source, let adNumber):
            return [
                "source": source,
                "ad_number": adNumber
            ]
        case .adFreeDayOfferShown(let source, let isIntro, let adsWatched):
            return [
                "source": source,
                "is_intro": isIntro ? 1 : 0,
                "ads_watched": adsWatched
            ]
        case .adFreeDayGranted(let source):
            return ["source": source]
        }
    }

    /// Adds the season dimension to a numbered-level event, or returns the
    /// parameters untouched when there is no season.
    ///
    /// The key is omitted rather than sent empty so an endless-Levels event is
    /// byte-identical to what it was before seasons existed — no historical
    /// comparison breaks, and `season_id is null` cleanly means "endless".
    private static func tagged(_ parameters: [String: Any], seasonID: String?) -> [String: Any] {
        guard let seasonID else { return parameters }
        var tagged = parameters
        tagged["season_id"] = seasonID
        return tagged
    }
}

enum AnalyticsService {
    static let cardTapSampleRate: Double = 0.2

    static func log(_ event: AnalyticsEvent) {
        Analytics.logEvent(event.name, parameters: event.parameters)
        if isVerboseLoggingEnabled {
            print("[Analytics] \(event.name): \(event.parameters)")
        }
    }

    static func shouldSample(_ rate: Double) -> Bool {
        Double.random(in: 0..<1) < rate
    }

    private static var isVerboseLoggingEnabled: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var title: String {
        switch self {
        case .system: return Strings.themeSystem
        case .light: return Strings.themeLight
        case .dark: return Strings.themeDark
        }
    }
}


// MARK:- FONTS
extension UIFont {
    class func righteous(size: CGFloat) -> UIFont {
        return UIFont.systemFont(ofSize: size, weight: .heavy)
    }

    class func patrickHand(size: CGFloat) -> UIFont {
        return UIFont.systemFont(ofSize: size, weight: .semibold)
    }
}

extension Font {
    static func righteous(size: CGFloat) -> Font {
        return .system(size: size, weight: .heavy, design: .rounded)
    }

    static func patrickHand(size: CGFloat) -> Font {
        return .system(size: size, weight: .semibold, design: .rounded)
    }
}

// MARK:- COLORS
extension Color {
    static var primaryColor: Color    { dynamicColor(light: (75, 63, 200), dark: (142, 129, 255)) }
    static var secundaryColor: Color  { dynamicColor(light: (255, 99, 64), dark: (255, 134, 109)) }
    static var easyGreen: Color       { dynamicColor(light: (40, 182, 126), dark: (73, 214, 151)) }
    static var hardAmber: Color       { dynamicColor(light: (245, 166, 35), dark: (255, 193, 87)) }
    static var medalGold: Color       { dynamicColor(light: (245, 196, 68), dark: (255, 209, 92)) }
    static var medalSilver: Color     { dynamicColor(light: (200, 206, 216), dark: (208, 214, 224)) }
    static var medalBronze: Color     { dynamicColor(light: (217, 155, 104), dark: (226, 168, 120)) }
    static var onMedal: Color         { dynamicColor(light: (43, 32, 12), dark: (43, 32, 12)) }
    static var freezeBlue: Color      { dynamicColor(light: (0, 145, 199), dark: (94, 200, 245)) }

    static var appBackground: Color   { dynamicColor(light: (247, 243, 237), dark: (17, 19, 31)) }
    static var surfacePrimary: Color  { dynamicColor(light: (255, 255, 255), dark: (30, 34, 52)) }
    static var surfaceSecondary: Color { dynamicColor(light: (239, 233, 227), dark: (40, 46, 69)) }
    static var textPrimary: Color     { dynamicColor(light: (28, 24, 48), dark: (244, 240, 255)) }
    static var textSecondary: Color   { dynamicColor(light: (122, 114, 145), dark: (164, 171, 196)) }
    static var surfaceBorder: Color   { dynamicColor(light: (225, 219, 235), dark: (65, 72, 98)) }
    static var shadowColor: Color     { dynamicColor(light: (28, 24, 48), dark: (0, 0, 0), lightOpacity: 0.08, darkOpacity: 0.32) }
    static var overlayBackdrop: Color { dynamicColor(light: (247, 243, 237), dark: (9, 11, 18), lightOpacity: 0.88, darkOpacity: 0.74) }

    // Backward-compatible aliases for existing call sites.
    static var grayBackground: Color  { appBackground }
    static var darkGrayColor: Color   { surfacePrimary }
    static var textMuted: Color       { textSecondary }

    static func make(_ red: Int, _ green: Int, _ blue: Int) -> Color {
        return Color(red: Double(red) / 255.0,
                     green: Double(green) / 255.0,
                     blue: Double(blue) / 255.0)
    }

    private static func dynamicColor(
        light: (Int, Int, Int),
        dark: (Int, Int, Int),
        lightOpacity: Double = 1,
        darkOpacity: Double = 1
    ) -> Color {
        Color(
            uiColor: UIColor { traitCollection in
                let palette = traitCollection.userInterfaceStyle == .dark ? dark : light
                let alpha = traitCollection.userInterfaceStyle == .dark ? darkOpacity : lightOpacity
                return UIColor(
                    red: CGFloat(palette.0) / 255.0,
                    green: CGFloat(palette.1) / 255.0,
                    blue: CGFloat(palette.2) / 255.0,
                    alpha: alpha
                )
            }
        )
    }
}

// MARK:- LAYOUT
/// Widths that keep a phone-shaped column readable on iPad. Every iPhone is
/// narrower than all of them, so capping at them changes nothing on a phone.
///
/// Deliberately not called `Layout`: a type with that name in this module
/// would hide SwiftUI's `Layout` protocol everywhere in the app.
enum ContentWidth {
    /// Lists and forms (Settings, Achievements).
    static let readable: CGFloat = 640
    /// The centred result, pause and quit cards shown over a board, and
    /// narrower stacks of controls (the multiplayer lobby, the finished-match
    /// actions, the intro carousels' buttons).
    static let modal: CGFloat = 460
    /// An intro carousel slide's title and subtitle, which would otherwise
    /// set as one very long line across a landscape iPad.
    static let carouselText: CGFloat = 560
}

extension View {
    /// Caps the view at `maxWidth` and centres it in whatever space is left,
    /// instead of letting it stretch edge to edge across an iPad.
    func readableWidth(_ maxWidth: CGFloat = ContentWidth.readable) -> some View {
        frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
    }
}
