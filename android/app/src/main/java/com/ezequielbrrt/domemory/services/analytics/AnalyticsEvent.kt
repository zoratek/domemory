package com.ezequielbrrt.domemory.services.analytics

/**
 * Every Firebase Analytics event this app logs, typed — the Android counterpart of iOS's
 * `enum AnalyticsEvent` (`ios/DoMemory/DoMemory/Configuration/AppConfiguration.swift`). Each
 * case owns its own event [name] and its typed [parameters]; a call site never passes a bare
 * event-name or parameter-key string — it constructs one of these and hands it to
 * [AnalyticsService.log].
 *
 * **Event names and parameter keys are copied verbatim from iOS** wherever an Android feature
 * has a direct iOS equivalent — both platforms log into the same Firebase project
 * (`domemory-c9211`), so a mismatched name would fragment one logical event across two
 * different rows in Analytics instead of one comparable funnel. Booleans are encoded as `1`/`0`
 * ints, matching iOS's own `isCustom ? 1 : 0` convention (Firebase has no native boolean
 * parameter type).
 *
 * Deliberately **not** ported from iOS's ~50-case enum: `levelStarsCredited` — on iOS it logs
 * from inside `LevelProgressService.recordCompletion`'s private `creditNewStars`, right where
 * the improvement-only credit amount is known. Android's `LevelProgressService`/
 * `SeasonProgressService` don't surface that per-call amount, and both classes are covered by
 * `LevelProgressServiceTest`/`SeasonProgressServiceTest` running as plain JVM unit tests with
 * no Firebase runtime — wiring a real `AnalyticsService.log` call into either would either
 * require plumbing the exact delta out through every caller or risk those tests touching an
 * uninitialized `FirebaseAnalytics` singleton. A correct implementation is a real follow-up,
 * not a five-minute addition, so it is left out rather than approximated with the wrong number.
 * Every other iOS event with an Android-equivalent screen/feature is represented below.
 */
sealed class AnalyticsEvent(val name: String, val parameters: Map<String, Any>) {

    data class ScreenView(val screenName: String, val screenClass: String) : AnalyticsEvent(
        name = "screen_view",
        parameters = mapOf("screen_name" to screenName, "screen_class" to screenClass),
    )

    data class DifficultySelected(val difficulty: String) : AnalyticsEvent(
        "difficulty_selected",
        mapOf("difficulty" to difficulty),
    )

    data class MenuLoaded(val difficulty: String) : AnalyticsEvent(
        "menu_loaded",
        mapOf("difficulty" to difficulty),
    )

    /** The player switched menu tab: `levels`, `mine` or `all`. */
    data class MenuTabSelected(val tab: String, val previousTab: String) : AnalyticsEvent(
        "menu_tab_selected",
        mapOf("tab" to tab, "previous_tab" to previousTab),
    )

    data class GameListLoaded(val difficulty: String, val gameCount: Int, val customCount: Int) : AnalyticsEvent(
        "game_list_loaded",
        mapOf("difficulty" to difficulty, "game_count" to gameCount, "custom_count" to customCount),
    )

    data class GameStarted(
        val source: String,
        val difficulty: String,
        val cardsCount: Int,
        val isCustom: Boolean,
    ) : AnalyticsEvent(
        "game_started",
        mapOf(
            "source" to source,
            "difficulty" to difficulty,
            "cards_count" to cardsCount,
            "is_custom" to isCustom.toAnalyticsInt(),
        ),
    )

    data class GameFinished(
        val result: String,
        val difficulty: String,
        val cardsCount: Int,
        val failedTries: Int,
        val timeRemaining: Int,
        val isCustom: Boolean,
    ) : AnalyticsEvent(
        "game_finished",
        mapOf(
            "result" to result,
            "difficulty" to difficulty,
            "cards_count" to cardsCount,
            "failed_tries" to failedTries,
            "time_remaining" to timeRemaining,
            "is_custom" to isCustom.toAnalyticsInt(),
        ),
    )

    /** Sampled at [AnalyticsService.CARD_TAP_SAMPLE_RATE] by the caller — every tap would be
     * far too high a volume, mirroring iOS's `AnalyticsService.shouldSample` guard in front of
     * `MemorizeViewModel.choose(card:)`. */
    data class CardTapped(val difficulty: String, val cardsCount: Int, val failedTries: Int) : AnalyticsEvent(
        "card_tapped",
        mapOf("difficulty" to difficulty, "cards_count" to cardsCount, "failed_tries" to failedTries),
    )

    data class PauseOpened(val difficulty: String, val timeRemaining: Int) : AnalyticsEvent(
        "pause_opened",
        mapOf("difficulty" to difficulty, "time_remaining" to timeRemaining),
    )

    data class ResumeTapped(val difficulty: String, val timeRemaining: Int) : AnalyticsEvent(
        "resume_tapped",
        mapOf("difficulty" to difficulty, "time_remaining" to timeRemaining),
    )

    data class QuitConfirmed(val difficulty: String, val timeRemaining: Int, val failedTries: Int) : AnalyticsEvent(
        "quit_confirmed",
        mapOf("difficulty" to difficulty, "time_remaining" to timeRemaining, "failed_tries" to failedTries),
    )

    data class RetryTapped(val difficulty: String, val cardsCount: Int, val source: String) : AnalyticsEvent(
        "retry_tapped",
        mapOf("difficulty" to difficulty, "cards_count" to cardsCount, "source" to source),
    )

    data class FavoriteToggled(val gameId: String, val isFavorite: Boolean) : AnalyticsEvent(
        "favorite_toggled",
        mapOf("game_id" to gameId, "is_favorite" to isFavorite.toAnalyticsInt()),
    )

    /** The create-memorama screen was opened: `menu_header` or `mine_empty_state`. Compare with
     * [CustomMemoramaCreated] for the share of players who finish building one. */
    data class CustomMemoramaCreateOpened(val source: String) : AnalyticsEvent(
        "custom_memorama_create_opened",
        mapOf("source" to source),
    )

    data class CustomMemoramaCreated(val gameId: String, val difficulty: String, val cardsCount: Int) : AnalyticsEvent(
        "custom_memorama_created",
        mapOf("game_id" to gameId, "difficulty" to difficulty, "cards_count" to cardsCount),
    )

    data class CustomMemoramaDeleted(val gameId: String) : AnalyticsEvent(
        "custom_memorama_deleted",
        mapOf("game_id" to gameId),
    )

    /** The player chose to `host` or `join` a room, before the backend accepts — so the gap
     * to [MultiplayerRoomCreated] / [MultiplayerRoomJoined] is abandonment or failure. */
    data class MultiplayerEntryTapped(val action: String) : AnalyticsEvent(
        "multiplayer_entry_tapped",
        mapOf("action" to action),
    )

    data class MultiplayerRoomCreated(val gameId: String, val isCustom: Boolean) : AnalyticsEvent(
        "multiplayer_room_created",
        mapOf("game_id" to gameId, "is_custom" to isCustom.toAnalyticsInt()),
    )

    data object MultiplayerRoomJoined : AnalyticsEvent("multiplayer_room_joined", emptyMap())

    data class MultiplayerGameStarted(val gameId: String) : AnalyticsEvent(
        "multiplayer_game_started",
        mapOf("game_id" to gameId),
    )

    data class MultiplayerGameFinished(val result: String) : AnalyticsEvent(
        "multiplayer_game_finished",
        mapOf("result" to result),
    )

    data class MultiplayerInviteSent(val source: String) : AnalyticsEvent(
        "multiplayer_invite_sent",
        mapOf("source" to source),
    )

    data object MultiplayerInviteOpened : AnalyticsEvent("multiplayer_invite_opened", emptyMap())

    data class AdLifecycle(val placement: String, val action: String) : AnalyticsEvent(
        "ad_lifecycle",
        mapOf("placement" to placement, "action" to action),
    )

    data class WhatsNewShown(val version: String) : AnalyticsEvent("whats_new_shown", mapOf("version" to version))

    data class WhatsNewDismissed(val version: String) : AnalyticsEvent(
        "whats_new_dismissed",
        mapOf("version" to version),
    )

    data class WhatsNewOpenedFromSettings(val version: String) : AnalyticsEvent(
        "whats_new_opened_from_settings",
        mapOf("version" to version),
    )

    data class NotificationPrimerShown(val source: String) : AnalyticsEvent(
        "notification_primer_shown",
        mapOf("source" to source),
    )

    data class NotificationPrimerCompleted(val source: String, val outcome: String) : AnalyticsEvent(
        "notification_primer_completed",
        mapOf("source" to source, "outcome" to outcome),
    )

    data class ReviewLinkOpened(val source: String) : AnalyticsEvent("review_link_opened", mapOf("source" to source))

    /** The player entered today's challenge: `card` or `widget` (the `domemory://daily` deep
     * link). Once per entry, unlike [DailyChallengeStarted], which repeats on every retry. */
    data class DailyChallengeOpened(val source: String, val streak: Int) : AnalyticsEvent(
        "daily_challenge_opened",
        mapOf("source" to source, "streak" to streak),
    )

    data class DailyChallengeStarted(val streak: Int) : AnalyticsEvent(
        "daily_challenge_started",
        mapOf("streak" to streak),
    )

    data class DailyChallengeFinished(val result: String, val streak: Int) : AnalyticsEvent(
        "daily_challenge_finished",
        mapOf("result" to result, "streak" to streak),
    )

    data class StreakMilestone(val days: Int) : AnalyticsEvent("streak_milestone", mapOf("days" to days))

    data class ResultShared(val source: String) : AnalyticsEvent("result_shared", mapOf("source" to source))

    data object OnboardingIntroCompleted : AnalyticsEvent("onboarding_intro_completed", emptyMap())

    data object OnboardingIntroSkipped : AnalyticsEvent("onboarding_intro_skipped", emptyMap())

    data class AchievementsOpened(val source: String) : AnalyticsEvent(
        "achievements_opened",
        mapOf("source" to source),
    )

    data object LeaderboardOpened : AnalyticsEvent("leaderboard_opened", emptyMap())

    data class LeaderboardBoardSelected(val board: String) : AnalyticsEvent(
        "leaderboard_board_selected",
        mapOf("board" to board),
    )

    data class LeaderboardNoticeAnswered(val accepted: Boolean) : AnalyticsEvent(
        "leaderboard_notice_answered",
        mapOf("accepted" to if (accepted) 1 else 0),
    )

    data object LeaderboardNameChanged : AnalyticsEvent("leaderboard_name_changed", emptyMap())

    data object LeaderboardLeft : AnalyticsEvent("leaderboard_left", emptyMap())

    data object LeaderboardRejoined : AnalyticsEvent("leaderboard_rejoined", emptyMap())

    /** Only logged when the pick differs from the current theme: `system`, `light`, `dark`. */
    data class ThemeChanged(val theme: String, val previousTheme: String) : AnalyticsEvent(
        "theme_changed",
        mapOf("theme" to theme, "previous_theme" to previousTheme),
    )

    // Season play reuses the numbered-level events rather than a parallel set, so the season
    // and endless-Levels funnels stay directly comparable — mirrors iOS's own doc comment on
    // this exact point. `seasonId` is omitted entirely (not sent empty) for endless Levels, so
    // an endless event stays byte-identical to what it was before Seasons existed.

    data class LevelStarted(val level: Int, val seasonId: String? = null) : AnalyticsEvent(
        "level_started",
        tagged(mapOf("level" to level), seasonId),
    )

    /** [powerUpsUsed] counts star power-ups bought during this attempt. */
    data class LevelFinished(
        val level: Int,
        val result: String,
        val stars: Int,
        val powerUpsUsed: Int,
        val seasonId: String? = null,
    ) : AnalyticsEvent(
        "level_finished",
        tagged(
            mapOf("level" to level, "result" to result, "stars" to stars, "power_ups_used" to powerUpsUsed),
            seasonId,
        ),
    )

    data class LevelUnlocked(val level: Int, val seasonId: String? = null) : AnalyticsEvent(
        "level_unlocked",
        tagged(mapOf("level" to level), seasonId),
    )

    data class LevelLifeConsumed(val livesRemaining: Int) : AnalyticsEvent(
        "level_life_consumed",
        mapOf("lives_remaining" to livesRemaining),
    )

    /** A loss just spent the day's last life. [LevelOutOfLivesShown] only fires later, when the
     * player taps a level with none left. */
    data class LevelLivesDepleted(val level: Int, val seasonId: String? = null) : AnalyticsEvent(
        "level_lives_depleted",
        tagged(mapOf("level" to level), seasonId),
    )

    data class LevelLifeGrantedFromAd(val livesRemaining: Int) : AnalyticsEvent(
        "level_life_granted_from_ad",
        mapOf("lives_remaining" to livesRemaining),
    )

    data class LevelOutOfLivesShown(val source: String) : AnalyticsEvent(
        "level_out_of_lives_shown",
        mapOf("source" to source),
    )

    data class LevelPowerUpUsed(
        val powerUp: String,
        val level: Int,
        val cost: Int,
        val balanceAfter: Int,
        val seasonId: String? = null,
    ) : AnalyticsEvent(
        "level_power_up_used",
        tagged(
            mapOf("power_up" to powerUp, "level" to level, "cost" to cost, "balance_after" to balanceAfter),
            seasonId,
        ),
    )

    data class LevelLifePurchasedWithStars(val cost: Int, val balanceAfter: Int) : AnalyticsEvent(
        "level_life_purchased_with_stars",
        mapOf("cost" to cost, "balance_after" to balanceAfter),
    )

    data class LevelSkipped(val level: Int, val cost: Int, val balanceAfter: Int) : AnalyticsEvent(
        "level_skipped",
        mapOf("level" to level, "cost" to cost, "balance_after" to balanceAfter),
    )

    data class LevelFailedByMistakes(val level: Int, val maxFailures: Int, val timeRemaining: Int) : AnalyticsEvent(
        "level_failed_by_mistakes",
        mapOf("level" to level, "max_failures" to maxFailures, "time_remaining" to timeRemaining),
    )

    data class LevelMistakesForgiven(val level: Int, val amount: Int, val source: String) : AnalyticsEvent(
        "level_mistakes_forgiven",
        mapOf("level" to level, "amount" to amount, "source" to source),
    )

    data class LevelsIntroShown(val source: String) : AnalyticsEvent("levels_intro_shown", mapOf("source" to source))

    data object LevelsIntroCompleted : AnalyticsEvent("levels_intro_completed", emptyMap())

    /** [slidesSeen] is how far the player got before skipping (1-based). */
    data class LevelsIntroSkipped(val slidesSeen: Int) : AnalyticsEvent(
        "levels_intro_skipped",
        mapOf("slides_seen" to slidesSeen),
    )

    /** The active season's card on the menu was tapped. Once per tap, unlike
     * [SeasonLevelsEntered], which also fires on returning from a level. */
    data class SeasonCardTapped(val seasonId: String) : AnalyticsEvent(
        "season_card_tapped",
        mapOf("season_id" to seasonId),
    )

    /** Fired every time a season's level map appears, including returning to it from a level —
     * distinct from the generic [ScreenView], which carries no season identity. */
    data class SeasonLevelsEntered(val seasonId: String) : AnalyticsEvent(
        "season_levels_entered",
        mapOf("season_id" to seasonId),
    )

    // The ad-free day offer (spec 12.3), in funnel order: entry tapped -> offer shown ->
    // watch tapped -> ad watched (once per ad) -> granted. The ad itself is still reported
    // through [AdLifecycle] under `ad_free_day_rewarded`; these carry its place in the chain.

    /** The "No Ads" pill or the Settings row was tapped. [state]: `idle`, `in_progress`, `active`. */
    data class AdFreeDayEntryTapped(val source: String, val state: String, val adsWatched: Int) : AnalyticsEvent(
        "ad_free_day_entry_tapped",
        mapOf("source" to source, "state" to state, "ads_watched" to adsWatched),
    )

    data class AdFreeDayOfferShown(val source: String, val isIntro: Boolean, val adsWatched: Int) : AnalyticsEvent(
        "ad_free_day_offer_shown",
        mapOf("source" to source, "is_intro" to isIntro.toAnalyticsInt(), "ads_watched" to adsWatched),
    )

    /** "Watch ad N of 2" was tapped with an ad ready. */
    data class AdFreeDayWatchTapped(val source: String, val adNumber: Int) : AnalyticsEvent(
        "ad_free_day_watch_tapped",
        mapOf("source" to source, "ad_number" to adNumber),
    )

    /** Rewarded ad N of the chain paid out. The last one is always followed by [AdFreeDayGranted]. */
    data class AdFreeDayAdWatched(val source: String, val adNumber: Int) : AnalyticsEvent(
        "ad_free_day_ad_watched",
        mapOf("source" to source, "ad_number" to adNumber),
    )

    data class AdFreeDayGranted(val source: String) : AnalyticsEvent(
        "ad_free_day_granted",
        mapOf("source" to source),
    )

    companion object {
        /** Adds the season dimension to a numbered-level event, or returns [parameters]
         * untouched when there is no season — mirrors iOS's private `tagged(_:seasonID:)`. */
        private fun tagged(parameters: Map<String, Any>, seasonId: String?): Map<String, Any> =
            if (seasonId == null) parameters else parameters + ("season_id" to seasonId)
    }
}

/** `1`/`0`, matching iOS's `isCustom ? 1 : 0` — Firebase Analytics has no boolean parameter
 * type, so every boolean flag in [AnalyticsEvent.parameters] is encoded this way. */
internal fun Boolean.toAnalyticsInt(): Int = if (this) 1 else 0
