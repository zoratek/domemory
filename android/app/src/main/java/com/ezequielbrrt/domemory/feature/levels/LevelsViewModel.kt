package com.ezequielbrrt.domemory.feature.levels

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.ezequielbrrt.domemory.services.analytics.AnalyticsEvent
import com.ezequielbrrt.domemory.services.haptics.HapticIntent
import com.ezequielbrrt.domemory.services.leaderboard.LeaderboardNameWords
import com.ezequielbrrt.domemory.services.leaderboard.LeaderboardService
import com.ezequielbrrt.domemory.services.levels.LevelLivesService
import com.ezequielbrrt.domemory.services.levels.LevelPowerUp
import com.ezequielbrrt.domemory.services.levels.LevelProgressService
import com.ezequielbrrt.domemory.services.levels.LevelsIntroGate
import com.ezequielbrrt.domemory.services.levels.StarWalletService
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/**
 * Thin wrapper over [LevelProgressService] / [LevelLivesService] / [StarWalletService]
 * for `LevelsScreen` — mirrors iOS's `LevelsViewModel`. The one rule this exists to make
 * testable without Compose: [attemptStart] is the spec 7.4 gate that must refuse to
 * start a level attempt at 0 daily lives, surfacing the out-of-lives prompt instead.
 */
class LevelsViewModel(
    private val progress: LevelProgressService,
    private val lives: LevelLivesService,
    private val wallet: StarWalletService,
    private val introGate: LevelsIntroGate,
    private val scope: CoroutineScope? = null,
    // Android counterpart of iOS's `LevelsView.onSelect` (`.select`/`.warning`) and
    // `LevelsViewModel.buyLifeWithStars`/`watchAdForLife` (`.reward`) — see this class's own
    // call sites below for the exact mapping. Bare callback, not a `HapticsService` reference,
    // for the same reason `GameViewModel.onHaptic` is: this class stays Android-framework-free
    // so it can be constructed and tested with no `HapticsService.initialize` ever having run.
    private val onHaptic: ((HapticIntent) -> Unit)? = null,
    /** Same bare-callback shape as [onHaptic], for the same reason — see
     * [com.ezequielbrrt.domemory.feature.game.GameViewModel]'s `onAnalytics` doc. */
    private val onAnalytics: ((AnalyticsEvent) -> Unit)? = null,
    private val leaderboard: LeaderboardService? = null,
    private val leaderboardName: ((LeaderboardNameWords) -> String)? = null,
) : ViewModel() {

    data class UiState(
        val livesRemaining: Int = LevelLivesService.MAX_LIVES,
        val starBalance: Int = 0,
        val showOutOfLivesPrompt: Boolean = false,
        val showIntro: Boolean = false,
        /** `levels_intro_shown.source` for the currently-showing (or most recently shown)
         * intro. Only ever `"info_button"` now that the automatic first-visit
         * presentation is gone, but kept as state so a future entry point reports itself
         * rather than inflating the button's numbers — the same reason iOS's
         * `LevelsIntroView` takes `source` as a parameter. */
        val introSource: String = "info_button",
        /** A one-shot heart animation the header owes the player; see [HeaderEffects.kt]. */
        val livesEffect: LivesEffect? = null,
        /** Sparkle over the star chip for a credit that just landed; never for a spend. */
        val starsCredited: Boolean = false,
        /** False until the kill switch says the leaderboard is on for this version. */
        val leaderboardAvailable: Boolean = false,
        /** The player's name while the one-time notice is owed, otherwise null. */
        val leaderboardNoticeName: String? = null,
    )

    /**
     * Whether [refresh] has populated the counters at least once. The defaults above are
     * placeholders, not a real previous state — comparing against them would break a heart
     * on the very first screen entry of a day with 2 lives left.
     */
    private var hasLoadedCounters = false

    fun refreshLeaderboard() {
        val service = leaderboard ?: return
        workScope.launch {
            val available = service.checkAvailability()
            val noticeName = if (available && !service.hasAcknowledgedNotice()) {
                service.ownNameWords()?.let { words -> leaderboardName?.invoke(words) }
            } else {
                null
            }
            _uiState.update { it.copy(leaderboardAvailable = available, leaderboardNoticeName = noticeName) }
        }
    }

    fun acceptLeaderboardNotice() {
        val service = leaderboard ?: return
        _uiState.update { it.copy(leaderboardNoticeName = null) }
        onAnalytics?.invoke(AnalyticsEvent.LeaderboardNoticeAnswered(accepted = true))
        workScope.launch {
            service.acknowledgeNotice()
            service.sync()
        }
    }

    fun declineLeaderboardNotice() {
        val service = leaderboard ?: return
        _uiState.update { it.copy(leaderboardNoticeName = null) }
        onAnalytics?.invoke(AnalyticsEvent.LeaderboardNoticeAnswered(accepted = false))
        workScope.launch { service.declineNotice() }
    }

    /** Clears a played heart effect so it does not replay on the next recomposition. */
    fun consumeLivesEffect() {
        _uiState.update { it.copy(livesEffect = null) }
    }

    fun consumeStarsCredited() {
        _uiState.update { it.copy(starsCredited = false) }
    }

    /** Applies fresh counters, attaching whatever animation the change deserves. */
    private fun UiState.withCounters(livesRemaining: Int, starBalance: Int = this.starBalance): UiState =
        if (!hasLoadedCounters) {
            copy(livesRemaining = livesRemaining, starBalance = starBalance)
        } else {
            copy(
                livesRemaining = livesRemaining,
                starBalance = starBalance,
                livesEffect = livesEffect(this.livesRemaining, livesRemaining) ?: livesEffect,
                starsCredited = starsCredited || starsCredited(this.starBalance, starBalance),
            )
        }

    private val workScope: CoroutineScope get() = scope ?: viewModelScope

    private val _uiState = MutableStateFlow(UiState())
    val uiState: StateFlow<UiState> = _uiState.asStateFlow()

    /** Live progress revision, so the tile grid recomposes as stars/unlocks arrive. */
    val progressRevision get() = progress.revision

    val highestUnlockedLevel: Int get() = progress.highestUnlockedLevel
    fun stars(level: Int): Int = progress.stars(level)
    fun isUnlocked(level: Int): Boolean = progress.isUnlocked(level)

    init {
        refresh()
    }

    /** Call after returning from a game so newly-earned stars/unlocks and the lives
     * count show up (mirrors iOS's `LevelsView.onDisappear { viewModel.refresh() }`). */
    fun refresh() {
        refreshLeaderboard()
        workScope.launch {
            // wallet.refresh(), not wallet.balance.value: a level win credits the wallet
            // directly through UserPreferences (LevelProgressService.recordCompletion),
            // so this cache can be stale until something explicitly re-pulls it.
            val starBalance = wallet.refresh()
            val livesRemaining = lives.remaining()
            _uiState.update { it.withCounters(livesRemaining = livesRemaining, starBalance = starBalance) }
            hasLoadedCounters = true
        }
    }

    /**
     * Opens the intro from the map header's info button — the only way in.
     *
     * It is deliberately no longer presented automatically on a player's first visit.
     * iOS dropped that in 4.3.0: Levels is the landing tab, so the intro landed on top
     * of a player who had not asked for it and raced the launch sequence's own covers.
     * [LevelsIntroGate] is still written on dismissal so the "seen it" flag stays
     * truthful for anything that wants it later.
     */
    fun presentIntro() {
        _uiState.update { it.copy(showIntro = true, introSource = "info_button") }
    }

    /** Persisted on dismissal, not on presentation — a kill mid-intro leaves the player
     * eligible to see it again (spec 7.9). */
    fun dismissIntro() {
        workScope.launch {
            introGate.markSeen()
            _uiState.update { it.copy(showIntro = false) }
        }
    }

    /**
     * The spec 7.4 gate: a player with 0 daily lives may not start a level attempt.
     * Returns true when the caller should navigate into the level; on a refusal it
     * surfaces the out-of-lives prompt instead and returns false.
     */
    suspend fun attemptStart(level: Int): Boolean {
        val remaining = lives.remaining()
        _uiState.update { it.copy(livesRemaining = remaining) }
        if (remaining <= 0) {
            // Refusal, not a selection — mirrors iOS's LevelsView.onSelect: "the modal
            // that follows is bad news."
            onHaptic?.invoke(HapticIntent.WARNING)
            onAnalytics?.invoke(AnalyticsEvent.LevelOutOfLivesShown(source = "level_tile"))
            _uiState.update { it.copy(showOutOfLivesPrompt = true) }
            return false
        }
        onHaptic?.invoke(HapticIntent.SELECT)
        return true
    }

    fun dismissOutOfLivesPrompt() {
        _uiState.update { it.copy(showOutOfLivesPrompt = false) }
    }

    /** Not gated on the Remove-Ads entitlement — the daily budget applies to purchasers
     * too (spec 7.4). */
    fun buyLifeWithStars() {
        workScope.launch {
            if (wallet.spend(LevelPowerUp.LIFE_COST)) {
                // Mirrors iOS's own comment on the equivalent button: "emits .reward on the
                // spend; a .tap here would double-buzz" — the composable's Buy-with-stars
                // button fires nothing of its own.
                onHaptic?.invoke(HapticIntent.REWARD)
                lives.refill(1)
                val livesRemaining = lives.remaining()
                val starBalance = wallet.balance.value
                onAnalytics?.invoke(
                    AnalyticsEvent.LevelLifePurchasedWithStars(cost = LevelPowerUp.LIFE_COST, balanceAfter = starBalance),
                )
                _uiState.update {
                    it.withCounters(livesRemaining = livesRemaining, starBalance = starBalance)
                        .copy(showOutOfLivesPrompt = false)
                }
            }
        }
    }

    /**
     * Ad-earned equivalent of [buyLifeWithStars] — no star spend, the ad already paid for
     * it. The composable layer calls this from a rewarded ad's earned-reward callback
     * (`AdsService.showRewarded`), never directly from a tap.
     */
    fun applyLifeRewardFromAd() {
        workScope.launch {
            // Mirrors iOS's watchAdForLife rewardHandler: fires .reward the moment the ad
            // actually pays out, not on the watch-ad button tap itself (that TAP lives at
            // the composable call site, before the ad even starts).
            onHaptic?.invoke(HapticIntent.REWARD)
            lives.refill(1)
            val livesRemaining = lives.remaining()
            onAnalytics?.invoke(AnalyticsEvent.LevelLifeGrantedFromAd(livesRemaining = livesRemaining))
            _uiState.update {
                it.withCounters(livesRemaining = livesRemaining).copy(showOutOfLivesPrompt = false)
            }
        }
    }
}
