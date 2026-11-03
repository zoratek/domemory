package com.ezequielbrrt.domemory

import android.content.Context
import androidx.glance.appwidget.updateAll
import com.ezequielbrrt.domemory.core.deeplink.DeepLinkRouter
import com.ezequielbrrt.domemory.core.time.DayKey
import com.ezequielbrrt.domemory.core.time.DayProvider
import com.ezequielbrrt.domemory.core.time.SystemDayProvider
import com.ezequielbrrt.domemory.data.prefs.UserPreferences
import com.ezequielbrrt.domemory.data.prefs.createUserPreferences
import com.ezequielbrrt.domemory.data.remote.FirebaseBoardCatalogSource
import com.ezequielbrrt.domemory.data.remote.FirebaseLeaderboardBackend
import com.ezequielbrrt.domemory.data.remote.FirebaseSeasonCatalogSource
import com.ezequielbrrt.domemory.data.repository.BoardCatalogRepository
import com.ezequielbrrt.domemory.data.repository.BoardCatalogSource
import com.ezequielbrrt.domemory.services.daily.DailyChallengeService
import com.ezequielbrrt.domemory.services.notifications.NotificationService
import com.ezequielbrrt.domemory.services.leaderboard.LeaderboardBackend
import com.ezequielbrrt.domemory.services.leaderboard.LeaderboardBoard
import com.ezequielbrrt.domemory.services.leaderboard.LeaderboardNameFormatter
import com.ezequielbrrt.domemory.services.leaderboard.LeaderboardService
import com.ezequielbrrt.domemory.services.multiplayer.MultiplayerService
import com.ezequielbrrt.domemory.services.whatsnew.WhatsNewManager
import com.ezequielbrrt.domemory.widget.DailyChallengeGlanceWidget
import com.ezequielbrrt.reviewflow.ReviewManager
import com.ezequielbrrt.domemory.services.levels.LevelProgressService
import com.ezequielbrrt.domemory.services.ads.AdFreeDayService
import com.ezequielbrrt.domemory.services.levels.LevelLivesService
import com.ezequielbrrt.domemory.services.levels.LevelsIntroGate
import com.ezequielbrrt.domemory.services.levels.StarWalletService
import com.ezequielbrrt.domemory.services.seasons.Season
import com.ezequielbrrt.domemory.services.seasons.SeasonCatalogService
import com.ezequielbrrt.domemory.services.seasons.SeasonCatalogSource
import com.ezequielbrrt.domemory.services.seasons.SeasonLevelProgressStore
import com.ezequielbrrt.domemory.services.seasons.SeasonProgressService
import com.ezequielbrrt.domemory.services.stats.ProfileStatsService
import com.ezequielbrrt.domemory.services.launch.LaunchSequence
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

/**
 * Manual DI (decision D4). Every service the app depends on is constructed here and
 * passed down, so a test can swap any of them for a fake without an annotation
 * processor.
 *
 * The player's chosen difficulty now lives in [prefs] (`UserPreferences.playerDifficulty`)
 * rather than as an in-memory var — see that accessor's doc for why it is a fresh key
 * rather than the legacy iOS `dificulty` one. [boardCatalog]'s custom-board list is
 * likewise sourced from `prefs.customMemoramas` instead of the old in-memory
 * `setCustomBoards()`.
 */
class AppContainer(
    context: Context,
    val dayProvider: DayProvider = SystemDayProvider,
    catalogSource: BoardCatalogSource = FirebaseBoardCatalogSource(),
    seasonCatalogSource: SeasonCatalogSource = FirebaseSeasonCatalogSource(),
    leaderboardBackend: LeaderboardBackend = FirebaseLeaderboardBackend(),
) {
    private val appContext = context.applicationContext

    /**
     * Work that must outlive an individual screen's ViewModel. At present this is only
     * the completion-stat write started as a player leaves a finished game; keeping it
     * here prevents NavController teardown from cancelling the DataStore edit.
     */
    val applicationScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /** The typed DataStore Preferences surface for every key in spec 13.2. */
    val prefs: UserPreferences = createUserPreferences(context)

    val boardCatalog = BoardCatalogRepository(
        remote = catalogSource,
        customBoardsSource = { prefs.customMemoramas.first() },
    )

    val levelProgress = LevelProgressService(prefs, applicationScope)
    val levelLives = LevelLivesService(prefs, dayProvider)

    /** The ad-free day (spec 12.3): the two-ad chain and the grant that turns ads off. */
    val adFreeDay = AdFreeDayService(prefs, dayProvider, applicationScope)
    val starWallet = StarWalletService(prefs, applicationScope)
    val levelsIntroGate = LevelsIntroGate(prefs)
    val dailyChallenge = DailyChallengeService(prefs, dayProvider)

    /** Lifetime aggregates + derived achievements (spec 13.2), the Settings > Achievements
     * screen's read side. `feature/game/GameViewModel` and `feature/multiplayer
     * .MultiplayerViewModel` record into the same [prefs] keys through a separate
     * `UserPreferencesProfileStatsRecorder(prefs)` at each construction site — not stored
     * here — matching the existing `UserPreferencesGameStatsRecorder(container.prefs)`
     * precedent (`NavGraph.kt`), rather than this container. */
    val profileStats = ProfileStatsService(prefs, dailyChallenge)
    val deepLinkRouter = DeepLinkRouter()
    val multiplayer = MultiplayerService()
    val whatsNew = WhatsNewManager(prefs, BuildConfig.VERSION_NAME)

    /** The board shared with iOS (spec 22). Stays inactive until the player answers its notice. */
    val leaderboard = LeaderboardService(
        prefs = prefs,
        backend = leaderboardBackend,
        appVersion = BuildConfig.VERSION_NAME,
        localScore = { board ->
            when (board) {
                LeaderboardBoard.STARS -> prefs.levelsLifetimeStars.first()
                LeaderboardBoard.STREAK -> prefs.dailyStreakLongest.first()
            }
        },
    )

    private val leaderboardLanguages by lazy {
        val json = runCatching {
            appContext.assets.open("leaderboard-names.json").bufferedReader().use { it.readText() }
        }.getOrDefault("{}")
        LeaderboardNameFormatter.parse(json)
    }

    /** Names in the reader's current language. A function, because the device language can change. */
    fun leaderboardNames(): LeaderboardNameFormatter {
        val tag = appContext.resources.configuration.locales[0].toLanguageTag()
        return LeaderboardNameFormatter(leaderboardLanguages[LeaderboardNameFormatter.languageKey(tag)])
    }

    init {
        // A game's scores are saved after onGameFinished fires, so a score rising is what
        // reliably triggers a send. drop(1) skips the value already stored at launch, because
        // launching the app must never send anything (spec 22.5).
        applicationScope.launch {
            combine(prefs.levelsLifetimeStars, prefs.dailyStreakLongest) { stars, streak -> stars to streak }
                .distinctUntilChanged()
                .drop(1)
                .collect { leaderboard.sync() }
        }
    }

    /** Spec 11.4's consent → ads → primer ordering, run once per process from the menu. */
    val launchSequence = LaunchSequence()

    /**
     * Spec 15.2's review policy, the counterpart of iOS's `AppReviews.manager`. One instance
     * for the process: `recordSuccessfulAction` (every `GameViewModel.onGameWon` site in
     * `NavGraph.kt`) and the presenter (`feature/review/ReviewInvitation.kt`, hosted by
     * `MainActivity`) must share it, and a pending ask survives activity recreation only if
     * the manager outlives the activity. History lives in the library's own
     * `SharedPreferences` file — a fresh install starts clean, there is nothing to migrate.
     */
    val reviews = ReviewManager(appContext)

    /** Local reminders (spec 11.2) — inactivity tiers, the streak-at-risk nudge, permission sync. */
    val notifications = NotificationService(appContext, prefs, dailyChallenge)

    /**
     * Spec 8's "finishing refreshes the streak-at-risk reminder and the home-screen widget",
     * and spec 11.2's "rescheduled ... after every game finish" for the streak reminder
     * specifically. [com.ezequielbrrt.domemory.feature.game.GameViewModel] is plain Kotlin
     * with no Android dependency, so it takes this as a bare `() -> Unit` rather than reaching
     * for [notifications] or the widget itself — wiring the two Android-framework side effects
     * together is this container's job, not the view model's.
     */
    val onDailyChallengeFinished: () -> Unit = {
        applicationScope.launch {
            notifications.refreshStreakAtRiskReminder()
            DailyChallengeGlanceWidget().updateAll(appContext)
        }
    }

    /**
     * Spec 11.2: "Both [inactivity tiers] are rescheduled (cancel + re-add) after every game
     * finish" — every mode, not just the Daily Challenge (that one additionally gets
     * [onDailyChallengeFinished] for the streak-specific reminder and the widget).
     */
    val onGameFinished: () -> Unit = {
        applicationScope.launch { notifications.scheduleInactivityReminders() }
        // Retries a score that was skipped or failed earlier. New scores arrive through init above.
        applicationScope.launch { leaderboard.sync() }
    }

    /**
     * Cache-first `/seasons` catalog (spec 9.7). [loadCached] is launched immediately below
     * so the season card has an answer as soon as the cache read finishes, without blocking
     * app startup on it; [SeasonCatalogService.refresh] then corrects it over the network.
     */
    val seasonCatalog = SeasonCatalogService(prefs, seasonCatalogSource)

    /**
     * One [SeasonProgressService] per season id for the life of the process, so two screens
     * observing the same season (the card, the map) share one cache and one `revision`
     * stream rather than each reading DataStore cold.
     */
    private val seasonProgressServices = mutableMapOf<String, SeasonProgressService>()

    init {
        applicationScope.launch {
            seasonCatalog.loadCached(todayKey())
            seasonCatalog.refresh(todayKey())
        }
    }

    /** Re-evaluates the active season against today with no network round trip (spec 9.4: foreground). */
    fun refreshActiveSeason() = seasonCatalog.refreshActive(todayKey())

    /** The [SeasonLevelProgressStore] for [season], memoized per season id. */
    fun seasonProgressStore(season: Season): SeasonLevelProgressStore {
        val progress = seasonProgressServices.getOrPut(season.id) {
            SeasonProgressService(season.id, prefs, applicationScope)
        }
        return SeasonLevelProgressStore(season, progress)
    }

    fun todayKey(): String = DayKey.of(dayProvider.today())
}
