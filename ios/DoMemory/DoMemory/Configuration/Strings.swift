//
//  Strings.swift
//  DoMemory
//
//  Created by Ezequiel Barreto on 23/09/20.
//

import Foundation

enum Strings {
    static let leaderboardTitle = NSLocalizedString("leaderboard_title", comment: "Leaderboard screen title")
    static let leaderboardTabStars = NSLocalizedString("leaderboard_tab_stars", comment: "Leaderboard tab for lifetime stars")
    static let leaderboardTabStreak = NSLocalizedString("leaderboard_tab_streak", comment: "Leaderboard tab for the longest Daily Challenge streak")
    static let leaderboardYou = NSLocalizedString("leaderboard_you", comment: "Marks the player's own row and score card")
    static func leaderboardRank(_ rank: Int) -> String {
        String(format: NSLocalizedString("leaderboard_rank_format", comment: "The player's rank on the board, %d = rank"), rank)
    }
    static let leaderboardCaptionStars = NSLocalizedString("leaderboard_caption_stars", comment: "Explains what the Stars board ranks")
    static let leaderboardCaptionStreak = NSLocalizedString("leaderboard_caption_streak", comment: "Explains what the Streak board ranks")
    static let leaderboardZeroStars = NSLocalizedString("leaderboard_zero_stars", comment: "Score card for a player with no stars")
    static let leaderboardZeroStreak = NSLocalizedString("leaderboard_zero_streak", comment: "Score card for a player with no streak")
    static let leaderboardPending = NSLocalizedString("leaderboard_pending", comment: "Score card while the player's score hasn't reached the board")
    static let leaderboardTop50 = NSLocalizedString("leaderboard_top_50", comment: "Heading above the ranked list")
    static func leaderboardPointsToTopStars(_ points: Int) -> String {
        String(format: NSLocalizedString("leaderboard_points_to_top_stars_format", comment: "Stars needed to enter the top 50, %d = count"), points)
    }
    static func leaderboardPointsToTopStreak(_ points: Int) -> String {
        String(format: NSLocalizedString("leaderboard_points_to_top_streak_format", comment: "Streak days needed to enter the top 50, %d = count"), points)
    }
    static let leaderboardEmpty = NSLocalizedString("leaderboard_empty", comment: "Leaderboard with no scores")
    static let leaderboardUnavailable = NSLocalizedString("leaderboard_unavailable", comment: "Leaderboard switched off")
    static let leaderboardFailed = NSLocalizedString("leaderboard_failed", comment: "Leaderboard failed to load")
    static let leaderboardRetry = NSLocalizedString("leaderboard_retry", comment: "Retry loading the leaderboard")
    static let leaderboardChangeName = NSLocalizedString("leaderboard_change_name", comment: "Button that opens the name picker")
    static let leaderboardNameTitle = NSLocalizedString("leaderboard_name_title", comment: "Name picker title")
    static let leaderboardNameAdjective = NSLocalizedString("leaderboard_name_adjective", comment: "Name picker label for the descriptive word")
    static let leaderboardNameAnimal = NSLocalizedString("leaderboard_name_animal", comment: "Name picker label for the animal")
    static let leaderboardNameSave = NSLocalizedString("leaderboard_name_save", comment: "Save the picked name")
    static let leaderboardNameFailed = NSLocalizedString("leaderboard_name_failed", comment: "Saving the picked name failed")
    static let leaderboardNoticeTitle = NSLocalizedString("leaderboard_notice_title", comment: "One-time leaderboard notice title")
    static func leaderboardNoticeBody(_ name: String) -> String {
        String(format: NSLocalizedString("leaderboard_notice_body_format", comment: "One-time leaderboard notice, %@ = the player's leaderboard name"), name)
    }
    static let leaderboardNoticeAccept = NSLocalizedString("leaderboard_notice_accept", comment: "Accept the leaderboard notice")
    static let appName = NSLocalizedString("common_app_name", comment: "Application display name")
    static let easy = NSLocalizedString("difficulty_easy", comment: "Easy difficulty level")
    static let easySubtitle = NSLocalizedString("difficulty_easy_subtitle", comment: "Subtitle for easy difficulty")
    static let medium = NSLocalizedString("difficulty_medium", comment: "Medium difficulty level")
    static let mediumSubtitle = NSLocalizedString("difficulty_medium_subtitle", comment: "Subtitle for medium difficulty")
    static let hard = NSLocalizedString("difficulty_hard", comment: "Hard difficulty level")
    static let hardSubtitle = NSLocalizedString("difficulty_hard_subtitle", comment: "Subtitle for hard difficulty")
    static let difficulty = NSLocalizedString("home_difficulty_title", comment: "Difficulty section title")
    static let askDifficulty = NSLocalizedString("home_select_difficulty_prompt", comment: "Prompt to select difficulty")
    static let veryHard = NSLocalizedString("difficulty_very_hard", comment: "Very hard difficulty level")
    static let veryHardSubtitle = NSLocalizedString("difficulty_very_hard_subtitle", comment: "Subtitle for very hard difficulty")
    static let dailyChallengeTitle = NSLocalizedString("daily_challenge_title", comment: "Daily challenge feature title")
    static let dailyChallengeSubtitle = NSLocalizedString("daily_challenge_subtitle", comment: "Daily challenge subtitle / call to action")
    static let dailyChallengeCompleted = NSLocalizedString("daily_challenge_completed", comment: "Daily challenge completed state for today")
    static func dailyChallengeStreak(_ days: Int) -> String {
        String(format: NSLocalizedString("daily_challenge_streak_format", comment: "Streak badge, %d = number of days"), days)
    }
    static let achievementsTitle = NSLocalizedString("achievements_title", comment: "Achievements screen title")
    static let achievementsSubtitle = NSLocalizedString("achievements_subtitle", comment: "Achievements settings row subtitle")
    static let achievementsStatsSection = NSLocalizedString("achievements_stats_section", comment: "Stats section header")
    static let achievementsBadgesSection = NSLocalizedString("achievements_badges_section", comment: "Badges section header")
    static let statTotalGames = NSLocalizedString("stat_total_games", comment: "Total games stat label")
    static let statTotalWins = NSLocalizedString("stat_total_wins", comment: "Total wins stat label")
    static let statWinRate = NSLocalizedString("stat_win_rate", comment: "Win rate stat label")
    static let statPerfectGames = NSLocalizedString("stat_perfect_games", comment: "Perfect games stat label")
    static let statLongestStreak = NSLocalizedString("stat_longest_streak", comment: "Longest streak stat label")
    static let statMultiplayerWins = NSLocalizedString("stat_multiplayer_wins", comment: "Multiplayer wins stat label")
    static let settingsTitle = NSLocalizedString("settings_title", comment: "Settings screen title")
    static let settingsDescription = NSLocalizedString("settings_description", comment: "Settings screen subtitle")
    static let settingsThemeTitle = NSLocalizedString("settings_theme_title", comment: "Theme setting title")
    static let settingsThemePrompt = NSLocalizedString("settings_theme_prompt", comment: "Theme picker subtitle")
    static let settingsRemoveAdsTitle = NSLocalizedString("settings_remove_ads_title", comment: "Remove ads setting title")
    static let settingsRemoveAdsDescription = NSLocalizedString("settings_remove_ads_description", comment: "Remove ads setting description")
    static let settingsRemoveAdsActionFormat = NSLocalizedString("settings_remove_ads_action_format", comment: "Remove ads purchase action with localized price")
    static let settingsRemoveAdsPurchased = NSLocalizedString("settings_remove_ads_purchased", comment: "Remove ads purchased state")
    static let settingsRemoveAdsPurchasedDescription = NSLocalizedString("settings_remove_ads_purchased_description", comment: "Remove ads purchased description")
    static let settingsRemoveAdsLoading = NSLocalizedString("settings_remove_ads_loading", comment: "Remove ads loading state")
    static let settingsRemoveAdsUnavailable = NSLocalizedString("settings_remove_ads_unavailable", comment: "Remove ads unavailable message")
    static let settingsRemoveAdsPending = NSLocalizedString("settings_remove_ads_pending", comment: "Remove ads pending message")
    static let settingsRemoveAdsNoRestore = NSLocalizedString("settings_remove_ads_no_restore", comment: "No restorable remove ads purchase message")
    static let settingsRewardedRemoveAdsTitle = NSLocalizedString("settings_rewarded_remove_ads_title", comment: "Rewarded temporary remove ads setting title")
    static func settingsRewardedRemoveAdsDescription(_ adCount: Int) -> String {
        String(format: NSLocalizedString("settings_rewarded_remove_ads_description", comment: "Rewarded temporary remove ads setting description, %d = ads to watch"), adCount)
    }
    static let settingsRewardedRemoveAdsAction = NSLocalizedString("settings_rewarded_remove_ads_action", comment: "Rewarded temporary remove ads button title")
    static let settingsRewardedRemoveAdsActive = NSLocalizedString("settings_rewarded_remove_ads_active", comment: "Rewarded temporary remove ads active state")
    static let settingsRewardedRemoveAdsActiveFormat = NSLocalizedString("settings_rewarded_remove_ads_active_format", comment: "Rewarded temporary remove ads active state with expiry time")
    static let settingsRewardedRemoveAdsSuccessTitle = NSLocalizedString("settings_rewarded_remove_ads_success_title", comment: "Rewarded temporary remove ads success alert title")
    static let settingsRewardedRemoveAdsSuccessMessage = NSLocalizedString("settings_rewarded_remove_ads_success_message", comment: "Rewarded temporary remove ads success alert message")
    static let settingsRestorePurchasesTitle = NSLocalizedString("settings_restore_purchases_title", comment: "Restore purchases setting title")
    static let settingsRestorePurchasesDescription = NSLocalizedString("settings_restore_purchases_description", comment: "Restore purchases setting description")
    static let settingsRestorePurchasesAction = NSLocalizedString("settings_restore_purchases_action", comment: "Restore purchases button title")
    static let settingsPurchaseSuccessTitle = NSLocalizedString("settings_purchase_success_title", comment: "Purchase successful alert title")
    static let settingsPurchaseSuccessMessage = NSLocalizedString("settings_purchase_success_message", comment: "Purchase successful alert message")
    static let settingsRestoreSuccessTitle = NSLocalizedString("settings_restore_success_title", comment: "Restore successful alert title")
    static let settingsRestoreSuccessMessage = NSLocalizedString("settings_restore_success_message", comment: "Restore successful alert message")
    static let themeSystem = NSLocalizedString("theme_system", comment: "System theme option")
    static let themeLight = NSLocalizedString("theme_light", comment: "Light theme option")
    static let themeDark = NSLocalizedString("theme_dark", comment: "Dark theme option")
    static let yourPoints = NSLocalizedString("game_points_label", comment: "Points label")
    static let time = NSLocalizedString("game_time_label", comment: "Time label")
    static let pause = NSLocalizedString("game_pause_title", comment: "Pause modal title")
    static let quit = NSLocalizedString("game_quit_confirmation", comment: "Quit confirmation prompt")
    static let cardFaceDown = NSLocalizedString("game_card_face_down", comment: "Accessibility label for a card that has not been turned over")
    static let cardFaceUp = NSLocalizedString("game_card_state_face_up", comment: "Accessibility value for a turned-over card that is not matched yet")
    static let cardMatched = NSLocalizedString("game_card_state_matched", comment: "Accessibility value for a card whose pair has been found")
    static let ok = NSLocalizedString("common_ok", comment: "OK action")
    static let cancel = NSLocalizedString("common_cancel", comment: "Cancel action")
    static let accept = NSLocalizedString("common_accept", comment: "Accept action")
    static let youLose = NSLocalizedString("game_lose_message", comment: "Lose modal description")
    static let rewardedHint = NSLocalizedString("game_rewarded_hint", comment: "Rewarded ad action for a game hint")
    static let adLoading = NSLocalizedString("ads_loading", comment: "Ad loading state")
    static let adLabel = NSLocalizedString("ads_label", comment: "Ad disclosure label")
    static let tryAgain = NSLocalizedString("game_try_again", comment: "Try again action")
    static let continueGame = NSLocalizedString("game_continue", comment: "Continue game action")
    static let goToMenu = NSLocalizedString("game_go_to_menu", comment: "Go to menu action")
    static let pairs = NSLocalizedString("game_pairs_label", comment: "Pairs stat label")
    static let remaining = NSLocalizedString("game_remaining_label", comment: "Remaining time stat label")
    static let errors = NSLocalizedString("game_errors_label", comment: "Errors stat label")
    static let youWin = NSLocalizedString("game_win_title", comment: "Win modal title")
    static let youWinDescription = NSLocalizedString("game_win_description", comment: "Win modal description")

    // Menu tabs
    static let tabAll = NSLocalizedString("menu_tab_all", comment: "Tab showing all games")
    static let tabMine = NSLocalizedString("menu_tab_mine", comment: "Tab showing user-created games")
    static let tabLevels = NSLocalizedString("menu_tab_levels", comment: "Tab showing the endless levels mode")

    // Levels mode
    static let levelsScreenTitle = NSLocalizedString("levels_screen_title", comment: "Levels map screen title")
    static func levelsCurrentLevelFormat(_ level: Int) -> String {
        String(format: NSLocalizedString("levels_current_level_format", comment: "Current level summary, %d = level number"), level)
    }
    static func levelTitle(_ level: Int) -> String {
        String(format: NSLocalizedString("level_title_format", comment: "Level board name / win-modal subtitle, %d = level number"), level)
    }
    static let levelCleared = NSLocalizedString("level_cleared", comment: "Win modal title when clearing a level")
    static let nextLevel = NSLocalizedString("level_next", comment: "Win modal primary action to advance to the next level")
    static let backToLevels = NSLocalizedString("level_back_to_levels", comment: "Win modal secondary action returning to the levels map")

    // Levels lives
    static let outOfLivesTitle = NSLocalizedString("levels_out_of_lives_title", comment: "Title shown when the player has no lives left today")
    static let outOfLivesMessage = NSLocalizedString("levels_out_of_lives_message", comment: "Message explaining how to get another life")
    /// Shown when no rewarded ad is available — Remove-Ads purchasers, or an
    /// unfilled ad slot. The default copy tells them to watch an ad they will
    /// never be offered.
    static let outOfLivesMessageNoAd = NSLocalizedString("levels_out_of_lives_message_no_ad", comment: "Out-of-lives message when no rewarded ad is available")
    static let watchAdForLife = NSLocalizedString("levels_watch_ad_for_life", comment: "Button to watch a rewarded ad for +1 life")
    static func livesRemainingFormat(_ remaining: Int, _ total: Int) -> String {
        String(format: NSLocalizedString("levels_lives_remaining_format", comment: "Accessibility label, %d = lives remaining, %d = max lives"), remaining, total)
    }

    // Star economy
    static let powerUpExtraTime = NSLocalizedString("levels_powerup_extra_time", comment: "Power-up that adds seconds to the clock")
    static let powerUpPeek = NSLocalizedString("levels_powerup_peek", comment: "Power-up that briefly reveals the whole board")
    static let powerUpFreeze = NSLocalizedString("levels_powerup_freeze", comment: "Power-up that pauses the countdown")
    static let powerUpRevealPair = NSLocalizedString("levels_powerup_reveal_pair", comment: "Power-up that reveals one matching pair")
    static func starBalanceFormat(_ balance: Int) -> String {
        String(format: NSLocalizedString("levels_star_balance_format", comment: "Accessibility label for the spendable star balance, %d = stars"), balance)
    }
    static func powerUpCostFormat(_ title: String, _ cost: Int) -> String {
        String(format: NSLocalizedString("levels_powerup_cost_format", comment: "Accessibility label, %@ = power-up name, %d = star cost"), title, cost)
    }
    static func buyLifeFormat(_ cost: Int) -> String {
        String(format: NSLocalizedString("levels_buy_life_format", comment: "Button to buy one life with stars, %d = star cost"), cost)
    }
    static func skipLevelFormat(_ cost: Int) -> String {
        String(format: NSLocalizedString("levels_skip_level_format", comment: "Button to skip the current level with stars, %d = star cost"), cost)
    }
    static let skipLevelConfirmTitle = NSLocalizedString("levels_skip_level_confirm_title", comment: "Confirmation title before skipping a level")
    static let skipLevelConfirmMessage = NSLocalizedString("levels_skip_level_confirm_message", comment: "Confirmation body explaining that a skipped level earns no stars")
    static let skipLevelConfirmAction = NSLocalizedString("levels_skip_level_confirm_action", comment: "Confirm action for skipping a level")

    // Lose modal rescue offers: a title naming what the player gets, then an
    // ad button and a star-price button side by side.
    static func loseOfferForgiveFormat(_ amount: Int) -> String {
        String(format: NSLocalizedString("lose_offer_forgive_format", comment: "Lose modal offer title: forgive mistakes and keep playing, %d = mistakes forgiven"), amount)
    }
    static let loseOfferExtraTime = NSLocalizedString("lose_offer_extra_time", comment: "Lose modal offer title: add 30 seconds to the clock and keep playing")
    static let loseOfferExtraLife = NSLocalizedString("lose_offer_extra_life", comment: "Lose modal offer title when out of lives: get one more life")
    static let loseOfferWatchAd = NSLocalizedString("lose_offer_watch_ad", comment: "Short button that pays for a lose modal offer with a rewarded ad")
    static func losePayStarsFormat(_ cost: Int) -> String {
        String(format: NSLocalizedString("lose_pay_stars_format", comment: "Accessibility label for the button that pays for a lose modal offer with stars, %d = star cost"), cost)
    }
    static let loseLifeAtStake = NSLocalizedString("lose_life_at_stake", comment: "Lose modal note: rescuing the current game means no life is spent")

    // Mistake budget
    static let loseTooManyMistakes = NSLocalizedString("levels_lose_too_many_mistakes", comment: "Lose modal message when the mistake budget is spent")
    static func timerFrozenFormat(_ seconds: Int) -> String {
        String(format: NSLocalizedString("levels_timer_frozen_format", comment: "Accessibility label while the Freeze power-up holds the clock, %d = seconds left"), seconds)
    }
    static func mistakesRemainingFormat(_ used: Int, _ total: Int) -> String {
        String(format: NSLocalizedString("levels_mistakes_remaining_format", comment: "Accessibility label, %1$d = mistakes made, %2$d = mistakes allowed"), used, total)
    }

    // Levels intro
    static let levelsIntroProgressTitle = NSLocalizedString("levels_intro_progress_title", comment: "Levels intro slide 1 title: endless progression")
    static let levelsIntroProgressSubtitle = NSLocalizedString("levels_intro_progress_subtitle", comment: "Levels intro slide 1 subtitle: clear a level to unlock the next")
    static let levelsIntroStarsTitle = NSLocalizedString("levels_intro_stars_title", comment: "Levels intro slide 2 title: earning and spending stars")
    static let levelsIntroStarsSubtitle = NSLocalizedString("levels_intro_stars_subtitle", comment: "Levels intro slide 2 subtitle: up to three stars per level, spendable")
    static let levelsIntroLivesTitle = NSLocalizedString("levels_intro_lives_title", comment: "Levels intro slide 3 title: daily lives")
    static func levelsIntroLivesSubtitle(_ maxLives: Int) -> String {
        String(format: NSLocalizedString("levels_intro_lives_subtitle", comment: "Levels intro slide 3 subtitle, %d = lives granted per day"), maxLives)
    }
    static let levelsIntroMistakesTitle = NSLocalizedString("levels_intro_mistakes_title", comment: "Levels intro slide 4 title: the mistake budget")
    static let levelsIntroMistakesSubtitle = NSLocalizedString("levels_intro_mistakes_subtitle", comment: "Levels intro slide 4 subtitle: limited mistakes per level, forgivable")
    static let levelsIntroDone = NSLocalizedString("levels_intro_done", comment: "Button dismissing the Levels intro on its last slide")
    static let levelsIntroInfoAccessibility = NSLocalizedString("levels_intro_info_accessibility", comment: "Accessibility label for the button that reopens the Levels intro")

    // Season levels
    /// Title for a season whose Firebase payload carries no strings the current
    /// locale can resolve — not the name of any real season, just something
    /// readable in place of an empty title.
    static let seasonFallbackTitle = NSLocalizedString("season_fallback_title", comment: "Generic title shown when a season supplies no strings for the current locale")
    /// Cleared levels out of the season's length, e.g. "7 / 20".
    static func seasonProgressFormat(_ cleared: Int, _ total: Int) -> String {
        String(format: NSLocalizedString("season_progress_format", comment: "Season progress, %1$d = levels cleared, %2$d = levels in the season"), cleared, total)
    }
    /// Spoken form of `seasonProgressFormat`. The visual "7 / 20" is read aloud
    /// as bare numbers with no idea what they count, so the progress bar gets a
    /// sentence instead.
    static func seasonProgressAccessibility(_ cleared: Int, _ total: Int) -> String {
        String(format: NSLocalizedString("season_progress_accessibility_format", comment: "Accessibility label for the season progress bar, %1$d = levels cleared, %2$d = levels in the season"), cleared, total)
    }
    /// How long the season is still running. Zero means it ends today, and one
    /// gets its own string rather than reading "1 days left".
    static func seasonDaysLeft(_ days: Int) -> String {
        switch days {
        case ...0: return seasonLastDay
        case 1: return seasonOneDayLeft
        default:
            return String(format: NSLocalizedString("season_days_left_format", comment: "Season countdown, %d = whole days remaining, always 2 or more"), days)
        }
    }
    static let seasonOneDayLeft = NSLocalizedString("season_one_day_left", comment: "Season countdown when exactly one day remains")
    static let seasonLastDay = NSLocalizedString("season_last_day", comment: "Season countdown on the season's final day")
    static let seasonCompleteBadge = NSLocalizedString("season_complete_badge", comment: "Menu card badge once every level of the season is cleared")
    static let seasonCompleteTitle = NSLocalizedString("season_complete_title", comment: "Title of the season-complete banner on the season level map")
    static let seasonCompleteMessage = NSLocalizedString("season_complete_message", comment: "Body of the season-complete banner explaining levels stay replayable")

    // Create memorama sheet
    static let createTitle = NSLocalizedString("menu_create_title", comment: "Sheet title for creating a new memorama")
    static let createName = NSLocalizedString("menu_create_name_label", comment: "Label for memorama name field")
    static let createNamePlaceholder = NSLocalizedString("menu_create_name_placeholder", comment: "Placeholder for memorama name field")
    static let createEmojisCount = NSLocalizedString("menu_create_emojis_label", comment: "Label prefix for emoji count")
    static let createMinimum = NSLocalizedString("menu_create_minimum_hint", comment: "Hint that at least 2 emojis are required")
    static let createAddEmoji = NSLocalizedString("menu_create_add_emoji", comment: "Button to add an emoji")
    static let createAdd = NSLocalizedString("menu_create_add", comment: "Confirm adding an emoji")
    static let createSave = NSLocalizedString("menu_create_save", comment: "Save button in create memorama sheet")

    // My memoramas empty state
    static let emptyMyGames = NSLocalizedString("menu_empty_mine_message", comment: "Empty state message for user-created games")
    static let emptyMyGamesAction = NSLocalizedString("menu_empty_mine_action", comment: "CTA button in empty state")
    static let menuRandomGame = NSLocalizedString("menu_random_game", comment: "Button title for starting a random game")
    static let menuFavoriteAdd = NSLocalizedString("menu_favorite_add", comment: "Accessibility label for adding a memorama to favorites")
    static let menuFavoriteRemove = NSLocalizedString("menu_favorite_remove", comment: "Accessibility label for removing a memorama from favorites")

    // Game stats
    static let statsPlayed = NSLocalizedString("stats_played_label", comment: "Played count label")
    static let statsWon = NSLocalizedString("stats_won_label", comment: "Won count label")

    // Delete action
    static let delete = NSLocalizedString("common_delete", comment: "Delete action in context menu")

    // Multiplayer
    static let multiplayerTitle = NSLocalizedString("multiplayer_title", comment: "Multiplayer screen title")
    static let multiplayerCreateRoom = NSLocalizedString("multiplayer_create_room", comment: "Create multiplayer room action")
    static let multiplayerJoinRoom = NSLocalizedString("multiplayer_join_room", comment: "Join multiplayer room action")
    static let multiplayerInviteFriend = NSLocalizedString("multiplayer_invite_friend", comment: "Share invite link to challenge a friend")
    static let shareResult = NSLocalizedString("share_result", comment: "Share game result action")
    static let introMultiplayerTitle = NSLocalizedString("intro_multiplayer_title", comment: "Onboarding intro: multiplayer title")
    static let introMultiplayerSubtitle = NSLocalizedString("intro_multiplayer_subtitle", comment: "Onboarding intro: multiplayer subtitle")
    static let introCustomTitle = NSLocalizedString("intro_custom_title", comment: "Onboarding intro: custom games title")
    static let introCustomSubtitle = NSLocalizedString("intro_custom_subtitle", comment: "Onboarding intro: custom games subtitle")
    static let introDailyTitle = NSLocalizedString("intro_daily_title", comment: "Onboarding intro: daily challenge title")
    static let introDailySubtitle = NSLocalizedString("intro_daily_subtitle", comment: "Onboarding intro: daily challenge subtitle")
    static let introSkip = NSLocalizedString("intro_skip", comment: "Onboarding intro: skip")
    static let introNext = NSLocalizedString("intro_next", comment: "Onboarding intro: next")
    static let introGetStarted = NSLocalizedString("intro_get_started", comment: "Onboarding intro: get started")
    static let multiplayerJoinDescription = NSLocalizedString("multiplayer_join_description", comment: "Join room instructions")
    static let multiplayerCodePlaceholder = NSLocalizedString("multiplayer_code_placeholder", comment: "Room code placeholder")
    static let multiplayerQRCode = NSLocalizedString("multiplayer_qr_code", comment: "QR code accessibility label")
    static let multiplayerStartGame = NSLocalizedString("multiplayer_start_game", comment: "Start multiplayer game action")
    static let multiplayerWaitingForPlayer = NSLocalizedString("multiplayer_waiting_for_player", comment: "Waiting for guest player state")
    static let multiplayerTapStartWhenReady = NSLocalizedString("multiplayer_tap_start_when_ready", comment: "Prompt shown to either player before they mark themselves ready, once a game is picked and both players are present")
    static let multiplayerWaitingForOpponentReady = NSLocalizedString("multiplayer_waiting_for_opponent_ready", comment: "Shown to a player who marked themselves ready, while waiting for the other player to do the same")
    static let multiplayerChooseGame = NSLocalizedString("multiplayer_choose_game", comment: "Host CTA to pick the room's game before start")
    static let multiplayerHostChooseGamePrompt = NSLocalizedString("multiplayer_host_choose_game_prompt", comment: "Host-facing status prompting them to pick a game")
    static let multiplayerWaitingForGame = NSLocalizedString("multiplayer_waiting_for_game", comment: "Guest-facing status while the host has not picked a game yet")
    static let multiplayerNoGamesForDifficulty = NSLocalizedString("multiplayer_no_games_for_difficulty", comment: "Empty state when the picked difficulty has no boards in the multiplayer game picker")
    static let multiplayerYourTurn = NSLocalizedString("multiplayer_your_turn", comment: "Current user turn state")
    static let multiplayerOpponentTurn = NSLocalizedString("multiplayer_opponent_turn", comment: "Opponent turn state")
    static let multiplayerReconnecting = NSLocalizedString("multiplayer_reconnecting", comment: "Reconnect grace state")
    static let multiplayerYouWon = NSLocalizedString("multiplayer_you_won", comment: "Winner state")
    static let multiplayerYouLost = NSLocalizedString("multiplayer_you_lost", comment: "Loser state")
    static let multiplayerDraw = NSLocalizedString("multiplayer_draw", comment: "Draw state")
    static let multiplayerRoomClosed = NSLocalizedString("multiplayer_room_closed", comment: "Closed room state")
    static let multiplayerYou = NSLocalizedString("multiplayer_you", comment: "Current player label")
    static let multiplayerOpponent = NSLocalizedString("multiplayer_opponent", comment: "Opponent player label")
    static let multiplayerFinalScore = NSLocalizedString("multiplayer_final_score", comment: "Final score label")
    static let multiplayerPlayAgain = NSLocalizedString("multiplayer_play_again", comment: "Restart multiplayer game action")
    static let multiplayerWaitingForRematch = NSLocalizedString("multiplayer_waiting_for_rematch", comment: "Guest waiting for host rematch state")
    static let multiplayerChooseAnotherGame = NSLocalizedString("multiplayer_choose_another_game", comment: "Choose another multiplayer game action")
    static let multiplayerHostName = NSLocalizedString("multiplayer_host_name", comment: "Default host name")
    static let multiplayerGuestName = NSLocalizedString("multiplayer_guest_name", comment: "Default guest name")
    static let multiplayerGenericError = NSLocalizedString("multiplayer_generic_error", comment: "Generic multiplayer error")
    static let multiplayerErrorFirebaseUnavailable = NSLocalizedString("multiplayer_error_firebase_unavailable", comment: "Firebase unavailable error")
    static let multiplayerErrorAuthentication = NSLocalizedString("multiplayer_error_authentication", comment: "Authentication error")
    static let multiplayerErrorRoomNotFound = NSLocalizedString("multiplayer_error_room_not_found", comment: "Room not found error")
    static let multiplayerErrorRoomFull = NSLocalizedString("multiplayer_error_room_full", comment: "Room full error")
    static let multiplayerErrorRoomUnavailable = NSLocalizedString("multiplayer_error_room_unavailable", comment: "Room unavailable error")
    static let multiplayerErrorInvalidMove = NSLocalizedString("multiplayer_error_invalid_move", comment: "Invalid move error")
    static let multiplayerErrorPermissionDenied = NSLocalizedString("multiplayer_error_permission_denied", comment: "Firebase rules denied multiplayer access")
    static let multiplayerErrorEncoding = NSLocalizedString("multiplayer_error_encoding", comment: "Encoding error")
    static let multiplayerErrorDecoding = NSLocalizedString("multiplayer_error_decoding", comment: "Decoding error")

    // Notifications settings
    static let settingsHapticsTitle = NSLocalizedString("settings_haptics_title", comment: "Haptic feedback setting title")
    static let settingsHapticsDescriptionOn = NSLocalizedString("settings_haptics_description_on", comment: "Haptics enabled description")
    static let settingsHapticsDescriptionOff = NSLocalizedString("settings_haptics_description_off", comment: "Haptics disabled description")
    static let settingsNotificationsTitle = NSLocalizedString("settings_notifications_title", comment: "Notifications setting title")
    static let settingsNotificationsDescriptionOn = NSLocalizedString("settings_notifications_description_on", comment: "Notifications enabled description")
    static let settingsNotificationsDescriptionOff = NSLocalizedString("settings_notifications_description_off", comment: "Notifications disabled description")
    static let settingsNotificationsDeniedTitle = NSLocalizedString("settings_notifications_denied_title", comment: "Alert title when notification permission denied")
    static let settingsNotificationsDeniedMessage = NSLocalizedString("settings_notifications_denied_message", comment: "Alert message when notification permission denied")
    static let settingsNotificationsOpenSettings = NSLocalizedString("settings_notifications_open_settings", comment: "Button to open iOS Settings")

    // Settings sections
    static let settingsSectionGame = NSLocalizedString("settings_section_game", comment: "Settings section: game")
    static let settingsSectionPreferences = NSLocalizedString("settings_section_preferences", comment: "Settings section: preferences")
    static let settingsSectionPurchases = NSLocalizedString("settings_section_purchases", comment: "Settings section: purchases")
    static let settingsSectionAbout = NSLocalizedString("settings_section_about", comment: "Settings section: about")

    // Notification permission primer
    static let notificationPrimerTitle = NSLocalizedString("notification_primer_title", comment: "Notification primer headline")
    static let notificationPrimerMessage = NSLocalizedString("notification_primer_message", comment: "Notification primer subtitle introducing the benefits")
    static let notificationPrimerBenefitStreak = NSLocalizedString("notification_primer_benefit_streak", comment: "Notification primer benefit: streak about to end")
    static let notificationPrimerBenefitInactive = NSLocalizedString("notification_primer_benefit_inactive", comment: "Notification primer benefit: haven't played in a while")
    static let notificationPrimerBenefitNoSpam = NSLocalizedString("notification_primer_benefit_no_spam", comment: "Notification primer benefit: reminders stay rare")
    static let notificationPrimerPreviewTitle = NSLocalizedString("notification_primer_preview_title", comment: "Title of the sample notification shown in the primer")
    static let notificationPrimerPreviewMessage = NSLocalizedString("notification_primer_preview_message", comment: "Body of the sample notification shown in the primer")
    static let notificationPrimerEnable = NSLocalizedString("notification_primer_enable", comment: "Notification primer primary button")
    static let notificationPrimerLater = NSLocalizedString("notification_primer_later", comment: "Notification primer secondary button")

    // Review and What's New settings rows
    static let settingsReviewTitle = NSLocalizedString("settings_review_title", comment: "Write a review setting title")
    static let settingsReviewDescription = NSLocalizedString("settings_review_description", comment: "Write a review setting description")
    static let settingsWhatsNewTitle = NSLocalizedString("settings_whats_new_title", comment: "What's New setting title")
    static let settingsWhatsNewDescription = NSLocalizedString("settings_whats_new_description", comment: "What's New setting description")
    static let settingsPrivacyOptionsTitle = NSLocalizedString("settings_privacy_options_title", comment: "Privacy options setting title, shown only where ad consent applies")
    static let settingsPrivacyOptionsDescription = NSLocalizedString("settings_privacy_options_description", comment: "Privacy options setting description")

    // What's New sheet (v3.0.0)
    static let whatsNewLeaderboardTitle = NSLocalizedString("whats_new_leaderboard_title", comment: "What's New 4.6.0 leaderboard title")
    static let whatsNewLeaderboardDescription = NSLocalizedString("whats_new_leaderboard_description", comment: "What's New 4.6.0 leaderboard description")
    static let whatsNewYourScoreTitle = NSLocalizedString("whats_new_your_score_title", comment: "What's New 4.6.0 score title")
    static let whatsNewYourScoreDescription = NSLocalizedString("whats_new_your_score_description", comment: "What's New 4.6.0 score description")
    static let whatsNewPickNameTitle = NSLocalizedString("whats_new_pick_name_title", comment: "What's New 4.6.0 name title")
    static let whatsNewPickNameDescription = NSLocalizedString("whats_new_pick_name_description", comment: "What's New 4.6.0 name description")
    static let whatsNewTitle = NSLocalizedString("whats_new_title", comment: "What's New sheet headline")
    static let whatsNewButton = NSLocalizedString("whats_new_button", comment: "What's New dismiss button")
    static let whatsNewMultiplayerTitle = NSLocalizedString("whats_new_multiplayer_title", comment: "Multiplayer feature title in What's New")
    static let whatsNewMultiplayerDescription = NSLocalizedString("whats_new_multiplayer_description", comment: "Multiplayer feature description in What's New")
    static let whatsNewRemindersTitle = NSLocalizedString("whats_new_reminders_title", comment: "Reminders feature title in What's New")
    static let whatsNewRemindersDescription = NSLocalizedString("whats_new_reminders_description", comment: "Reminders feature description in What's New")
    static let whatsNewThemeTitle = NSLocalizedString("whats_new_theme_title", comment: "Theme feature title in What's New")
    static let whatsNewThemeDescription = NSLocalizedString("whats_new_theme_description", comment: "Theme feature description in What's New")
    static let whatsNewHintTitle = NSLocalizedString("whats_new_hint_title", comment: "Hint feature title in What's New")
    static let whatsNewHintDescription = NSLocalizedString("whats_new_hint_description", comment: "Hint feature description in What's New")

    // What's New sheet (v3.1.0)
    static let whatsNewGamesTitle = NSLocalizedString("whats_new_games_title", comment: "New games feature title in What's New")
    static let whatsNewGamesDescription = NSLocalizedString("whats_new_games_description", comment: "New games feature description in What's New")

    // What's New sheet (v4.0.0)
    static let whatsNewLevelsTitle = NSLocalizedString("whats_new_levels_title", comment: "Levels mode title in What's New")
    static let whatsNewLevelsDescription = NSLocalizedString("whats_new_levels_description", comment: "Levels mode description in What's New")
    static let whatsNewStarsTitle = NSLocalizedString("whats_new_stars_title", comment: "Star rating title in What's New")
    static let whatsNewStarsDescription = NSLocalizedString("whats_new_stars_description", comment: "Star rating description in What's New")
    static let whatsNewPowerUpsTitle = NSLocalizedString("whats_new_powerups_title", comment: "Power-ups title in What's New")
    static let whatsNewPowerUpsDescription = NSLocalizedString("whats_new_powerups_description", comment: "Power-ups description in What's New")
    static let whatsNewLivesTitle = NSLocalizedString("whats_new_lives_title", comment: "Daily lives and mistake budget title in What's New")
    static let whatsNewLivesDescription = NSLocalizedString("whats_new_lives_description", comment: "Daily lives and mistake budget description in What's New")

    // What's New sheet (v4.2.0)
    static let whatsNewSeasonsTitle = NSLocalizedString("whats_new_seasons_title", comment: "Season Levels feature title in What's New")
    static let whatsNewSeasonsDescription = NSLocalizedString("whats_new_seasons_description", comment: "Season Levels feature description in What's New")
    static let whatsNewSeasonArtworkTitle = NSLocalizedString("whats_new_season_artwork_title", comment: "Season artwork title in What's New")
    static let whatsNewSeasonArtworkDescription = NSLocalizedString("whats_new_season_artwork_description", comment: "Season artwork description in What's New")
    static let whatsNewTapToPlayTitle = NSLocalizedString("whats_new_tap_to_play_title", comment: "Level map tap feedback title in What's New")
    static let whatsNewTapToPlayDescription = NSLocalizedString("whats_new_tap_to_play_description", comment: "Level map tap feedback description in What's New")
    static let whatsNewSeasonProgressTitle = NSLocalizedString("whats_new_season_progress_title", comment: "Season progress title in What's New")
    static let whatsNewSeasonProgressDescription = NSLocalizedString("whats_new_season_progress_description", comment: "Season progress description in What's New")

    // What's New sheet (v4.3.0)
    static let whatsNewMultiplayerHostTitle = NSLocalizedString("whats_new_multiplayer_host_title", comment: "Host-first multiplayer title in What's New")
    static let whatsNewMultiplayerHostDescription = NSLocalizedString("whats_new_multiplayer_host_description", comment: "Host-first multiplayer description in What's New")
    static let whatsNewMultiplayerReadyTitle = NSLocalizedString("whats_new_multiplayer_ready_title", comment: "Multiplayer ready check title in What's New")
    static let whatsNewMultiplayerReadyDescription = NSLocalizedString("whats_new_multiplayer_ready_description", comment: "Multiplayer ready check description in What's New")

    // Ad-free day offer (pill + sheet)
    static let adFreeDayPillTitle = NSLocalizedString("ad_free_day_pill_title", comment: "Floating No Ads pill, idle")
    static func adFreeDayPillProgress(_ watched: Int, of required: Int) -> String {
        String(format: NSLocalizedString("ad_free_day_pill_progress_format", comment: "Floating No Ads pill with chain progress, %d = ads watched, %d = ads required"), watched, required)
    }
    static func adFreeDayPillActive(_ remaining: String) -> String {
        String(format: NSLocalizedString("ad_free_day_pill_active_format", comment: "Floating pill while the ad-free day runs, %@ = time left like 18h"), remaining)
    }
    static let adFreeDayIntroTitle = NSLocalizedString("ad_free_day_intro_title", comment: "Ad-free day sheet title on the first open (apology)")
    static func adFreeDayIntroMessage(_ adCount: Int) -> String {
        String(format: NSLocalizedString("ad_free_day_intro_message", comment: "Ad-free day sheet message on the first open, %d = ads to watch"), adCount)
    }
    static func adFreeDayIntroWatch(_ index: Int, of required: Int) -> String {
        String(format: NSLocalizedString("ad_free_day_intro_watch_format", comment: "Ad-free day primary button on the first open, %d = ad number, %d = ads required"), index, required)
    }
    static let adFreeDayTitle = NSLocalizedString("ad_free_day_title", comment: "Ad-free day sheet title on return visits")
    static func adFreeDayMessage(_ adCount: Int) -> String {
        String(format: NSLocalizedString("ad_free_day_message", comment: "Ad-free day sheet message on return visits, %d = ads to watch"), adCount)
    }
    static func adFreeDayWatch(_ index: Int, of required: Int) -> String {
        String(format: NSLocalizedString("ad_free_day_watch_format", comment: "Ad-free day primary button, %d = ad number, %d = ads required"), index, required)
    }
    static func adFreeDayStepAd(_ index: Int) -> String {
        String(format: NSLocalizedString("ad_free_day_step_ad_format", comment: "Ad-free day stepper label under an ad node, %d = ad number"), index)
    }
    static let adFreeDayStepReward = NSLocalizedString("ad_free_day_step_reward", comment: "Ad-free day stepper label under the reward node")
    static let adFreeDayHalfwayHint = NSLocalizedString("ad_free_day_halfway_hint", comment: "Ad-free day status line after the first ad")
    static let adFreeDayNoFill = NSLocalizedString("ad_free_day_no_fill", comment: "Ad-free day status line when no rewarded ad is available")
    static let adFreeDayTryAgain = NSLocalizedString("ad_free_day_try_again", comment: "Ad-free day primary button when no ad was available")
    static func adFreeDayActive(_ until: String) -> String {
        String(format: NSLocalizedString("ad_free_day_active_format", comment: "Ad-free day status line while the grant runs, %@ = expiry time"), until)
    }
    static let adFreeDayBack = NSLocalizedString("ad_free_day_back", comment: "Ad-free day primary button once the day is granted")
    static func adFreeDayRemoveForever(_ price: String) -> String {
        String(format: NSLocalizedString("ad_free_day_remove_forever_format", comment: "Ad-free day upsell link to the Remove Ads purchase, %@ = localized price"), price)
    }
    static let adFreeDayNotNow = NSLocalizedString("ad_free_day_not_now", comment: "Ad-free day dismiss button")
}
