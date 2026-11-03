package com.ezequielbrrt.domemory.navigation

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import androidx.navigation.NavHostController
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import com.ezequielbrrt.domemory.AppContainer
import com.ezequielbrrt.domemory.BuildConfig
import com.ezequielbrrt.domemory.core.deeplink.DeepLink
import com.ezequielbrrt.domemory.core.model.Difficulty
import com.ezequielbrrt.domemory.core.model.GameMode
import com.ezequielbrrt.domemory.core.model.LevelContext
import com.ezequielbrrt.domemory.feature.game.GameScreen
import com.ezequielbrrt.domemory.feature.game.GameViewModel
import com.ezequielbrrt.domemory.feature.game.UserPreferencesGameStatsRecorder
import com.ezequielbrrt.domemory.feature.debug.DebugMenuScreen
import com.ezequielbrrt.domemory.feature.levels.LevelsIntroOverlay
import com.ezequielbrrt.domemory.feature.levels.LevelsViewModel
import com.ezequielbrrt.domemory.feature.menu.CreateMemoramaScreen
import com.ezequielbrrt.domemory.feature.menu.CreateMemoramaViewModel
import com.ezequielbrrt.domemory.feature.menu.MenuScreen
import com.ezequielbrrt.domemory.feature.menu.MenuViewModel
import com.ezequielbrrt.domemory.feature.notifications.NotificationPrimerHost
import com.ezequielbrrt.domemory.feature.notifications.isNotificationAuthorized
import com.ezequielbrrt.domemory.feature.onboarding.OnboardingScreen
import com.ezequielbrrt.domemory.feature.onboarding.OnboardingViewModel
import com.ezequielbrrt.domemory.feature.leaderboard.LeaderboardScreen
import com.ezequielbrrt.domemory.feature.leaderboard.LeaderboardViewModel
import com.ezequielbrrt.domemory.feature.seasons.SeasonLevelsScreen
import com.ezequielbrrt.domemory.feature.seasons.SeasonLevelsViewModel
import com.ezequielbrrt.domemory.feature.settings.AchievementsScreen
import com.ezequielbrrt.domemory.feature.settings.AchievementsViewModel
import com.ezequielbrrt.domemory.feature.settings.SettingsScreen
import com.ezequielbrrt.domemory.feature.settings.SettingsViewModel
import com.ezequielbrrt.domemory.services.ads.AdPlacement
import com.ezequielbrrt.domemory.services.ads.AdsService
import com.ezequielbrrt.domemory.services.ads.ConsentService
import com.ezequielbrrt.domemory.services.ads.findActivity
import com.ezequielbrrt.domemory.services.analytics.AnalyticsEvent
import com.ezequielbrrt.domemory.services.analytics.AnalyticsService
import com.ezequielbrrt.domemory.services.haptics.HapticIntent
import com.ezequielbrrt.domemory.services.haptics.HapticsService
import com.ezequielbrrt.domemory.services.launch.LaunchSequence
import com.ezequielbrrt.domemory.services.levels.LevelLivesService
import com.ezequielbrrt.domemory.services.stats.UserPreferencesProfileStatsRecorder
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.withResumed
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Replaces `Phase1Root` (spec 2): Menu -> Game -> back, plus Menu -> create memorama ->
 * back to Menu. Every screen owns a real [androidx.lifecycle.ViewModel] scoped to its
 * nav back-stack entry, so leaving a screen (a `popBackStack`) tears its view model down
 * through the normal `ViewModelStore` -> `onCleared()` path — no more `remember`-only
 * state, and no more a "try again" leaving a countdown ticking forever (`Phase1Root`'s
 * own doc comment named that exact bug; see [GameViewModel.restart]).
 */
private object Routes {
    const val MENU = "menu"
    const val ONBOARDING = "onboarding"
    const val SETTINGS = "settings"
    const val ACHIEVEMENTS = "achievements"
    const val DEBUG_MENU = "debug_menu"
    const val CREATE_MEMORAMA = "create_memorama"
    const val LEVEL_GAME = "level/{level}"
    const val SEASON_LEVELS = "season/{seasonId}"
    const val SEASON_GAME = "season/{seasonId}/level/{level}"
    const val DAILY_GAME = "daily"
    const val MULTIPLAYER = "multiplayer?code={code}"
    private const val GAME_PATTERN = "game/{boardId}/{difficultyKey}"
    const val GAME = GAME_PATTERN

    fun game(boardId: String, difficulty: Difficulty) = "game/$boardId/${difficulty.key}"
    fun level(level: Int) = "level/$level"
    fun seasonLevels(seasonId: String) = "season/$seasonId"
    fun seasonGame(seasonId: String, level: Int) = "season/$seasonId/level/$level"
    fun multiplayer(code: String = "") = "multiplayer?code=$code"
}

@Composable
fun NavGraph(
    container: AppContainer,
    hasOnboarded: Boolean,
    onWhatsNew: () -> Unit,
    navController: NavHostController = rememberNavController(),
) {
    // Resolved once and captured by every route below — a full-screen ad needs the
    // Activity to present against; DoMemory is single-activity, so this is MainActivity
    // for the life of the process.
    val activity = LocalContext.current.findActivity()

    // A domemory://daily link can arrive before onboarding resolves (spec 11.1: "links can
    // arrive before the UI exists"); only route it once there's a Menu to land on, and only
    // if today isn't already locked — mirrors the no-op DailyChallengeCard tap above.
    val pendingDeepLink by container.deepLinkRouter.pending.collectAsState()
    // Keyed on the active season too: on a first launch a season link can arrive before
    // the catalog has one, and waits for it (briefly, see DeepLink.OpenSeason.resolve).
    val activeSeasonId = container.seasonCatalog.activeSeason.collectAsState().value?.id
    LaunchedEffect(hasOnboarded, pendingDeepLink, activeSeasonId) {
        if (!hasOnboarded) return@LaunchedEffect
        when (val link = container.deepLinkRouter.pending.value) {
            is DeepLink.Daily -> {
                val alreadyDone = container.dailyChallenge.isCompletedToday()
                container.deepLinkRouter.consume()
                if (!alreadyDone) {
                    AnalyticsService.log(
                        AnalyticsEvent.DailyChallengeOpened(source = "widget", streak = container.dailyChallenge.currentStreak()),
                    )
                    navController.navigate(Routes.DAILY_GAME)
                }
            }
            is DeepLink.Join -> {
                val code = (container.deepLinkRouter.pending.value as DeepLink.Join).code
                container.deepLinkRouter.consume()
                navController.navigate(Routes.multiplayer(code))
            }
            is DeepLink.OpenSeason -> {
                when (link.resolve(activeSeasonId, System.currentTimeMillis())) {
                    DeepLink.OpenSeason.Resolution.OPEN -> {
                        container.deepLinkRouter.consume()
                        activeSeasonId?.let { navController.navigate(Routes.seasonLevels(it)) }
                    }
                    DeepLink.OpenSeason.Resolution.WAIT -> Unit
                    DeepLink.OpenSeason.Resolution.DROP -> container.deepLinkRouter.consume()
                }
            }
            null -> Unit
        }
    }

    NavHost(navController = navController, startDestination = if (hasOnboarded) Routes.MENU else Routes.ONBOARDING) {
        composable(Routes.ONBOARDING) {
            val ifResumed = rememberResumedGuard()
            val viewModel: OnboardingViewModel = viewModel(factory = viewModelFactory { initializer { OnboardingViewModel(container.prefs) } })
            val state by viewModel.state.collectAsState()
            val onOnboardingComplete = { ifResumed { navController.navigate(Routes.MENU) { popUpTo(Routes.ONBOARDING) { inclusive = true } } } }
            OnboardingScreen(
                state,
                onNext = { viewModel.completeIntro(onOnboardingComplete) },
                onSkip = { viewModel.skipIntro(onOnboardingComplete) },
            )
        }
        composable(Routes.MENU) {
            val ifResumed = rememberResumedGuard()
            val viewModel: MenuViewModel = viewModel(
                factory = viewModelFactory {
                    initializer { MenuViewModel(container.boardCatalog, container.prefs) }
                },
            )
            val state by viewModel.state.collectAsState()
            LaunchedEffect(Unit) {
                AnalyticsService.log(AnalyticsEvent.ScreenView(screenName = "menu", screenClass = "MenuScreen"))
            }
            val levelsViewModel: LevelsViewModel = viewModel(
                factory = viewModelFactory {
                    initializer {
                        LevelsViewModel(
                            progress = container.levelProgress,
                            lives = container.levelLives,
                            wallet = container.starWallet,
                            introGate = container.levelsIntroGate,
                            onHaptic = HapticsService::fire,
                            onAnalytics = AnalyticsService::log,
                            leaderboard = container.leaderboard,
                            leaderboardName = { container.leaderboardNames().name(it) },
                        )
                    }
                },
            )
            val levelsUiState by levelsViewModel.uiState.collectAsState()
            // Only the top destination stays composed, so this runs every time the menu comes
            // back into view — the counterpart of iOS's `LevelsView.onAppear { refresh() }`. It
            // picks up lives and stars changed elsewhere, e.g. the debug menu's "Restart lives".
            LaunchedEffect(Unit) { levelsViewModel.refresh() }
            val activeSeason by container.seasonCatalog.activeSeason.collectAsState()
            val dailyStreak by container.prefs.dailyStreakCurrent.collectAsState(initial = 0)
            val dailyLastAttemptDay by container.prefs.dailyLastAttemptDay.collectAsState(initial = null)
            val isDailyCompletedToday = dailyLastAttemptDay == container.todayKey()
            // Null until DataStore's real value arrives, so the primer never flashes on screen
            // for one frame and the launch sequence never finishes on a placeholder — spec
            // 11.3 shows it once per install, not once per launch.
            val notificationPrimerShown by container.prefs.notificationPrimerShown.collectAsState(initial = null)
            // Spec 11.4: consent → Mobile Ads → primer → finished, once per process. Waits
            // for the menu to be resumed (iOS waits for the app to be active) and runs on the
            // application scope, so leaving the menu cannot cancel it half way.
            val launchStage by container.launchSequence.stage.collectAsState()
            val menuLifecycle = LocalLifecycleOwner.current.lifecycle
            LaunchedEffect(Unit) {
                val host = activity ?: return@LaunchedEffect
                menuLifecycle.withResumed {}
                container.launchSequence.start(
                    scope = container.applicationScope,
                    gatherConsent = { withContext(Dispatchers.Main) { ConsentService.gatherConsent(host) } },
                    startAdsIfAllowed = { AdsService.startIfAllowed(host.applicationContext) },
                )
            }

            Box(Modifier.fillMaxSize()) {
                MenuScreen(
                    state = state,
                    onSelectTab = viewModel::selectTab,
                    onDifficultyChange = viewModel::setDifficulty,
                    onToggleFavorite = viewModel::toggleFavorite,
                    onDeleteCustomMemorama = viewModel::deleteCustomMemorama,
                    onBoardSelected = { board ->
                        ifResumed {
                            navController.navigate(Routes.game(board.id, state.difficulty))
                        }
                    },
                    onRandomGame = {
                        ifResumed {
                            viewModel.randomGame()?.let { board ->
                                navController.navigate(Routes.game(board.id, state.difficulty))
                            }
                        }
                    },
                    onCreateMemorama = { ifResumed { navController.navigate(Routes.CREATE_MEMORAMA) } },
                    onMultiplayer = { ifResumed { navController.navigate(Routes.multiplayer()) } },
                    onSettings = { ifResumed { navController.navigate(Routes.SETTINGS) } },
                    levelsViewModel = levelsViewModel,
                    onLevelSelected = { ifResumed { navController.navigate(Routes.level(it)) } },
                    leaderboardAvailable = levelsUiState.leaderboardAvailable,
                    leaderboardContent = {
                        val formatter = remember { container.leaderboardNames() }
                        val leaderboardViewModel: LeaderboardViewModel = viewModel(
                            factory = viewModelFactory {
                                initializer {
                                    LeaderboardViewModel(
                                        service = container.leaderboard,
                                        formatter = formatter,
                                        onAnalytics = AnalyticsService::log,
                                    )
                                }
                            },
                        )
                        LeaderboardScreen(viewModel = leaderboardViewModel, formatter = formatter)
                    },
                    activeSeason = activeSeason,
                    activeSeasonStore = activeSeason?.let { container.seasonProgressStore(it) },
                    onSeasonSelected = { season -> ifResumed { navController.navigate(Routes.seasonLevels(season.id)) } },
                    dailyStreak = dailyStreak,
                    isDailyChallengeCompletedToday = isDailyCompletedToday,
                    onDailyChallengeSelected = {
                        ifResumed {
                            // Mirrors the domemory://daily deep link: a no-op once today is done,
                            // since there's no result screen yet to send the player back to (spec 11.1).
                            // Matches iOS's DailyChallengeCard/CompactDailyChallengeCard buttons,
                            // which only fire .tap inside the same !isCompleted guard.
                            if (!isDailyCompletedToday) {
                                HapticsService.fire(HapticIntent.TAP)
                                AnalyticsService.log(AnalyticsEvent.DailyChallengeOpened(source = "card", streak = dailyStreak))
                                navController.navigate(Routes.DAILY_GAME)
                            }
                        }
                    },
                )

                // A sibling of MenuScreen, not something LevelsScreen renders itself: iOS's
                // `.fullScreenCover(isPresented: $showIntro)` (LevelsView.swift) covers the
                // whole screen, Menu chrome included, and LevelsScreen is only ever composed
                // as the Levels tab's content, below that chrome — see LevelsScreen.kt's own
                // comment on this exact point.
                if (levelsUiState.showIntro) {
                    LevelsIntroOverlay(source = levelsUiState.introSource, onDismiss = levelsViewModel::dismissIntro)
                }

                // Spec 11.3: "Shown once per install on the menu, and reused by the Settings
                // toggle" (SettingsScreen hosts the same primer for its own toggle). Skipped,
                // as iOS's `guard authorizationStatus == .notDetermined` skips it, when the OS
                // already delivers this app's notifications — nothing to ask for.
                val context = LocalContext.current
                val primerDue = notificationPrimerShown?.let { shown -> !shown && !isNotificationAuthorized(context) }
                LaunchedEffect(launchStage, primerDue) {
                    if (launchStage == LaunchSequence.Stage.PRIMER && primerDue == false) {
                        container.launchSequence.primerFinished()
                    }
                }
                NotificationPrimerHost(
                    visible = launchStage == LaunchSequence.Stage.PRIMER && primerDue == true,
                    source = "menu",
                    onAuthorized = { container.applicationScope.launch { container.notifications.activateReminders() } },
                    onFinished = {
                        container.applicationScope.launch { container.prefs.setNotificationPrimerShown(true) }
                        container.launchSequence.primerFinished()
                    },
                )
            }
        }

        composable(
            route = Routes.MULTIPLAYER,
            arguments = listOf(navArgument("code") { type = NavType.StringType; defaultValue = "" }),
        ) { entry ->
            val ifResumed = rememberResumedGuard()
            val initialCode = entry.arguments?.getString("code").orEmpty()
            val viewModel: com.ezequielbrrt.domemory.feature.multiplayer.MultiplayerViewModel = viewModel(
                factory = viewModelFactory {
                    initializer {
                        com.ezequielbrrt.domemory.feature.multiplayer.MultiplayerViewModel(
                            container.multiplayer,
                            UserPreferencesProfileStatsRecorder(container.prefs),
                            onHaptic = HapticsService::fire,
                            onAnalytics = AnalyticsService::log,
                        )
                    }
                },
            )
            // Spec 10.4 step 3: the game picker offers every difficulty of the raw catalog
            // (unlike the All tab's boards(difficulty), boards here is already unfiltered),
            // plus every custom board, the same merge boards(difficulty) does for the All tab.
            val catalogBoards by container.boardCatalog.boards.collectAsState(initial = emptyList())
            val customBoards by container.boardCatalog.customBoardsFlow.collectAsState(initial = emptyList())
            val boards = catalogBoards + customBoards
            com.ezequielbrrt.domemory.feature.multiplayer.MultiplayerScreen(
                boards = boards,
                vm = viewModel,
                initialCode = initialCode,
                onBack = { ifResumed { navController.popBackStack() } },
            )
        }

        composable(Routes.DAILY_GAME) {
            val ifResumed = rememberResumedGuard()
            // Daily Challenge takes the *player's* stored difficulty for the clock/pie, not
            // the board's own — the board always declares medium (spec 8's "medium difficulty"
            // is the board's, distinct from the player setting that drives the timer).
            val playerDifficulty by container.prefs.playerDifficulty.collectAsState(initial = Difficulty.MEDIUM)
            val viewModel: GameViewModel = viewModel(
                factory = viewModelFactory {
                    initializer {
                        GameViewModel(
                            board = container.dailyChallenge.boardForToday(),
                            mode = GameMode.DailyChallenge,
                            playerDifficulty = playerDifficulty,
                            stats = UserPreferencesGameStatsRecorder(container.prefs),
                            profileStats = UserPreferencesProfileStatsRecorder(container.prefs),
                            statsScope = container.applicationScope,
                            dailyChallenge = container.dailyChallenge,
                            onDailyChallengeFinished = container.onDailyChallengeFinished,
                            onGameFinished = container.onGameFinished,
                            onCompletionInterstitial = { difficulty, durationMs ->
                                AdsService.notifyGameFinished(activity, difficulty, durationMs)
                            },
                            onHaptic = HapticsService::fire,
                            onGameWon = { container.reviews.recordSuccessfulAction(BuildConfig.VERSION_NAME) },
                            onAnalytics = AnalyticsService::log,
                            initialSource = "daily_challenge",
                        )
                    }
                },
            )
            val state by viewModel.state.collectAsState()
            val dailyStreak by container.prefs.dailyStreakCurrent.collectAsState(initial = 0)
            GameScreen(
                state,
                viewModel::choose,
                { if (state.isPaused) viewModel.resume() else viewModel.pause() },
                {
                    ifResumed {
                        // The Daily Challenge has no lose-screen rescue to protect, so — like
                        // free play's own onQuit below — this doubles as the mid-game abandon.
                        AnalyticsService.log(
                            AnalyticsEvent.QuitConfirmed(
                                difficulty = state.recordedDifficulty.key,
                                timeRemaining = state.timeRemaining.toInt(),
                                failedTries = state.failedTries,
                            ),
                        )
                        HapticsService.fire(HapticIntent.TAP)
                        navController.popBackStack()
                    }
                },
                {
                    AnalyticsService.log(
                        AnalyticsEvent.RetryTapped(
                            difficulty = state.recordedDifficulty.key,
                            cardsCount = state.cards.size,
                            source = if (state.outcome != null) "lose_modal" else "pause_modal",
                        ),
                    )
                    HapticsService.fire(HapticIntent.TAP)
                    viewModel.restart()
                },
                onBackgrounded = viewModel::pauseForBackground,
                onWatchAdForHint = { onFinished ->
                    HapticsService.fire(HapticIntent.TAP)
                    AdsService.showRewarded(
                        activity,
                        AdPlacement.GAME_REWARDED_HINT,
                        onReward = {},
                        onDismissed = { rewarded ->
                            if (rewarded) {
                                viewModel.applyHintReward()
                                viewModel.resume()
                            }
                            onFinished()
                        },
                    )
                },
                isDailyChallenge = true,
                dailyStreak = dailyStreak,
            )
        }

        composable(Routes.SEASON_LEVELS, arguments = listOf(navArgument("seasonId") { type = NavType.StringType })) { entry ->
            val ifResumed = rememberResumedGuard()
            val seasonId = entry.arguments?.getString("seasonId").orEmpty()
            val seasons by container.seasonCatalog.seasons.collectAsState()
            val season = seasons.firstOrNull { it.id == seasonId }
            if (season == null) {
                // The season expired or vanished from the catalog between selection and
                // this composition (e.g. a foreground re-check dropped it) — bounce back
                // rather than crash on a null season.
                LaunchedEffect(Unit) { navController.popBackStack() }
                return@composable
            }
            val store = remember(season.id) { container.seasonProgressStore(season) }
            val seasonLevelsViewModel: SeasonLevelsViewModel = viewModel(
                factory = viewModelFactory {
                    initializer {
                        SeasonLevelsViewModel(
                            lives = container.levelLives,
                            wallet = container.starWallet,
                            onHaptic = HapticsService::fire,
                        )
                    }
                },
            )
            SeasonLevelsScreen(
                season = season,
                store = store,
                viewModel = seasonLevelsViewModel,
                todayKey = container.todayKey(),
                onLevelSelected = { level -> ifResumed { navController.navigate(Routes.seasonGame(season.id, level)) } },
                onBack = { ifResumed { navController.popBackStack() } },
            )
        }

        composable(
            route = Routes.SEASON_GAME,
            arguments = listOf(
                navArgument("seasonId") { type = NavType.StringType },
                navArgument("level") { type = NavType.IntType },
            ),
        ) { entry ->
            val ifResumed = rememberResumedGuard()
            val seasonId = entry.arguments?.getString("seasonId").orEmpty()
            val level = entry.arguments?.getInt("level") ?: 1
            val seasons by container.seasonCatalog.seasons.collectAsState()
            val season = seasons.firstOrNull { it.id == seasonId }
            if (season == null) {
                LaunchedEffect(Unit) { navController.popBackStack() }
                return@composable
            }
            val store = remember(season.id) { container.seasonProgressStore(season) }
            val viewModel: GameViewModel = viewModel(
                factory = viewModelFactory {
                    initializer {
                        GameViewModel(
                            board = store.board(level),
                            mode = GameMode.Level(
                                LevelContext(number = level, store = store, seasonId = season.id, levelCount = season.levelCount),
                            ),
                            stats = UserPreferencesGameStatsRecorder(container.prefs),
                            profileStats = UserPreferencesProfileStatsRecorder(container.prefs),
                            statsScope = container.applicationScope,
                            levelLives = container.levelLives,
                            // Power-ups and the lose-screen star purchases are "Levels and
                            // Seasons only" (spec 7.6) — season play is a GameMode.Level the
                            // same way endless is, so it needs the same wallet.
                            starWallet = container.starWallet,
                            onGameFinished = container.onGameFinished,
                            onCompletionInterstitial = { difficulty, durationMs ->
                                AdsService.notifyGameFinished(activity, difficulty, durationMs)
                            },
                            onHaptic = HapticsService::fire,
                            onGameWon = { container.reviews.recordSuccessfulAction(BuildConfig.VERSION_NAME) },
                            onAnalytics = AnalyticsService::log,
                            // This route's own `onNextLevel` below re-navigates here for the
                            // following level rather than advancing in place, so a "next
                            // level" transition reports the same "season_levels" source as
                            // a normal map entry — unlike iOS's `trackGameStarted`, which has
                            // a dedicated "next_level" source for that case. Documented
                            // simplification: less granular in Analytics, no behavior change.
                            initialSource = "season_levels",
                        )
                    }
                },
            )
            val state by viewModel.state.collectAsState()
            val starBalance by container.starWallet.balance.collectAsState()
            val coroutineScope = rememberCoroutineScope()

            // The same SeasonLevelsViewModel instance still on the season map's back-stack
            // entry — refreshed on the way out so newly-spent lives/stars show up the moment
            // the player is back on the map (mirrors LEVEL_GAME's identical wiring for the
            // endless map, and iOS's `SeasonLevelsView.onDisappear { viewModel.refresh() }`).
            val seasonLevelsEntry = remember { navController.getBackStackEntry(Routes.seasonLevels(seasonId)) }
            val seasonLevelsViewModel: SeasonLevelsViewModel = viewModel(
                viewModelStoreOwner = seasonLevelsEntry,
                factory = viewModelFactory {
                    initializer {
                        SeasonLevelsViewModel(
                            lives = container.levelLives,
                            wallet = container.starWallet,
                            onHaptic = HapticsService::fire,
                            onAnalytics = AnalyticsService::log,
                        )
                    }
                },
            )
            DisposableEffect(Unit) {
                onDispose { seasonLevelsViewModel.refresh() }
            }

            GameScreen(
                state = state,
                onChoose = viewModel::choose,
                onPauseToggle = { if (state.isPaused) viewModel.resume() else viewModel.pause() },
                onBackgrounded = viewModel::pauseForBackground,
                onQuit = {
                    ifResumed {
                        // A season loss is deferred exactly like an endless one (see
                        // GameViewModel's class doc) — quitting without this would leave the
                        // life unspent and the attempt unrecorded. acknowledgeLossAndQuit()
                        // fires its own TAP haptic.
                        viewModel.acknowledgeLossAndQuit()
                        navController.popBackStack()
                    }
                },
                onQuitDuringPlay = {
                    ifResumed {
                        // Mid-game abandon (spec §3.6) — no outcome exists yet, so unlike
                        // [onQuit] above this must not spend a life or touch stats. Mirrors
                        // iOS's `tapOnExit()`, the Quit modal's confirm handler.
                        AnalyticsService.log(
                            AnalyticsEvent.QuitConfirmed(
                                difficulty = state.recordedDifficulty.key,
                                timeRemaining = state.timeRemaining.toInt(),
                                failedTries = state.failedTries,
                            ),
                        )
                        HapticsService.fire(HapticIntent.TAP)
                        navController.popBackStack()
                    }
                },
                onRetry = {
                    // Out of lives after this loss commits: stay put rather than navigate
                    // away. `GameUiState.livesRemaining` is updated by the same `retry()`
                    // call, so the still-mounted lose overlay re-renders into its
                    // out-of-lives state in place — matching iOS's `LoseModal`, which
                    // re-renders instead of dismissing once `tapOnTryAgain` finds no lives
                    // left (spec 7.7).
                    coroutineScope.launch { viewModel.retry() }
                },
                onNextLevel = {
                    ifResumed {
                        navController.popBackStack()
                        navController.navigate(Routes.seasonGame(seasonId, level + 1))
                    }
                },
                isLevel = true,
                starBalance = starBalance,
                onBuyExtraTime = { coroutineScope.launch { viewModel.buyExtraTime() } },
                onBuyPeek = { coroutineScope.launch { viewModel.buyPeek() } },
                onBuyFreeze = { coroutineScope.launch { viewModel.buyFreeze() } },
                onBuyRevealPair = { coroutineScope.launch { viewModel.buyRevealPair() } },
                onBuyLifeWithStars = { coroutineScope.launch { viewModel.buyLifeWithStars() } },
                onForgiveMistakesWithStars = { coroutineScope.launch { viewModel.forgiveMistakesWithStars() } },
                onSkipLevelWithStars = {
                    ifResumed {
                        coroutineScope.launch {
                            if (viewModel.skipLevelWithStars()) navController.popBackStack()
                        }
                    }
                },
                onWatchAdForLife = { onFinished ->
                    HapticsService.fire(HapticIntent.TAP)
                    AdsService.showRewarded(
                        activity,
                        AdPlacement.LEVELS_REWARDED_LIFE,
                        onReward = { coroutineScope.launch { viewModel.applyLifeReward() } },
                        // Drives the lose overlay's loading state (spec: iOS's
                        // `isRewardedAdInProgress`) regardless of whether the ad was
                        // actually earned — mirrors `onWatchAdForHint` below.
                        onDismissed = { onFinished() },
                    )
                },
                onWatchAdToForgive = { onFinished ->
                    HapticsService.fire(HapticIntent.TAP)
                    AdsService.showRewarded(
                        activity,
                        AdPlacement.LEVELS_REWARDED_FORGIVE,
                        onReward = { coroutineScope.launch { viewModel.applyForgiveMistakesReward() } },
                        onDismissed = { onFinished() },
                    )
                },
                onWatchAdForHint = { onFinished ->
                    HapticsService.fire(HapticIntent.TAP)
                    AdsService.showRewarded(
                        activity,
                        AdPlacement.GAME_REWARDED_HINT,
                        onReward = {},
                        onDismissed = { rewarded ->
                            if (rewarded) {
                                viewModel.applyHintReward()
                                viewModel.resume()
                            }
                            onFinished()
                        },
                    )
                },
            )
        }

        composable(Routes.LEVEL_GAME, arguments = listOf(navArgument("level") { type = NavType.IntType })) { entry ->
            val ifResumed = rememberResumedGuard()
            val level = entry.arguments?.getInt("level") ?: 1
            val store = container.levelProgress
            val viewModel: GameViewModel = viewModel(
                factory = viewModelFactory {
                    initializer {
                        GameViewModel(
                            board = store.board(level),
                            mode = GameMode.Level(com.ezequielbrrt.domemory.core.model.LevelContext(level, store)),
                            stats = UserPreferencesGameStatsRecorder(container.prefs),
                            profileStats = UserPreferencesProfileStatsRecorder(container.prefs),
                            statsScope = container.applicationScope,
                            levelLives = container.levelLives,
                            starWallet = container.starWallet,
                            onGameFinished = container.onGameFinished,
                            onCompletionInterstitial = { difficulty, durationMs ->
                                AdsService.notifyGameFinished(activity, difficulty, durationMs)
                            },
                            onHaptic = HapticsService::fire,
                            onGameWon = { container.reviews.recordSuccessfulAction(BuildConfig.VERSION_NAME) },
                            onAnalytics = AnalyticsService::log,
                            // Same simplification as the Season route above: this route's
                            // own `onNextLevel` below re-navigates here for the following
                            // level, so a "next level" transition reports the same
                            // "levels_tab" source as a normal map entry rather than iOS's
                            // dedicated "next_level" source. Documented simplification: less
                            // granular in Analytics, no behavior change.
                            initialSource = "levels_tab",
                        )
                    }
                },
            )
            val state by viewModel.state.collectAsState()
            val starBalance by container.starWallet.balance.collectAsState()
            val coroutineScope = rememberCoroutineScope()

            // The same LevelsViewModel instance still on the Menu back-stack entry —
            // refreshed on the way out so newly-spent lives and stars show up the moment
            // the player is back on the map (mirrors iOS's `LevelsView.onDisappear`).
            val menuEntry = remember { navController.getBackStackEntry(Routes.MENU) }
            val levelsViewModel: LevelsViewModel = viewModel(
                viewModelStoreOwner = menuEntry,
                factory = viewModelFactory {
                    initializer {
                        LevelsViewModel(
                            progress = container.levelProgress,
                            lives = container.levelLives,
                            wallet = container.starWallet,
                            introGate = container.levelsIntroGate,
                            onHaptic = HapticsService::fire,
                            onAnalytics = AnalyticsService::log,
                            leaderboard = container.leaderboard,
                            leaderboardName = { container.leaderboardNames().name(it) },
                        )
                    }
                },
            )
            DisposableEffect(Unit) {
                onDispose { levelsViewModel.refresh() }
            }

            GameScreen(
                state = state,
                onChoose = viewModel::choose,
                onPauseToggle = { if (state.isPaused) viewModel.resume() else viewModel.pause() },
                onBackgrounded = viewModel::pauseForBackground,
                onQuit = {
                    ifResumed {
                        viewModel.acknowledgeLossAndQuit()
                        navController.popBackStack()
                    }
                },
                onQuitDuringPlay = {
                    ifResumed {
                        // Mid-game abandon (spec §3.6) — no outcome exists yet, so unlike
                        // [onQuit] above this must not spend a life or touch stats. Mirrors
                        // iOS's `tapOnExit()`, the Quit modal's confirm handler.
                        AnalyticsService.log(
                            AnalyticsEvent.QuitConfirmed(
                                difficulty = state.recordedDifficulty.key,
                                timeRemaining = state.timeRemaining.toInt(),
                                failedTries = state.failedTries,
                            ),
                        )
                        HapticsService.fire(HapticIntent.TAP)
                        navController.popBackStack()
                    }
                },
                onRetry = {
                    // Out of lives after this loss commits: stay put rather than navigate
                    // away. `GameUiState.livesRemaining` is updated by the same `retry()`
                    // call, so the still-mounted lose overlay re-renders into its
                    // out-of-lives state in place — matching iOS's `LoseModal`, which
                    // re-renders instead of dismissing once `tapOnTryAgain` finds no lives
                    // left (spec 7.4, 7.7).
                    coroutineScope.launch { viewModel.retry() }
                },
                onNextLevel = {
                    ifResumed {
                        navController.popBackStack()
                        navController.navigate(Routes.level(level + 1))
                    }
                },
                isLevel = true,
                starBalance = starBalance,
                onBuyExtraTime = { coroutineScope.launch { viewModel.buyExtraTime() } },
                onBuyPeek = { coroutineScope.launch { viewModel.buyPeek() } },
                onBuyFreeze = { coroutineScope.launch { viewModel.buyFreeze() } },
                onBuyRevealPair = { coroutineScope.launch { viewModel.buyRevealPair() } },
                onBuyLifeWithStars = { coroutineScope.launch { viewModel.buyLifeWithStars() } },
                onForgiveMistakesWithStars = { coroutineScope.launch { viewModel.forgiveMistakesWithStars() } },
                onSkipLevelWithStars = {
                    ifResumed {
                        coroutineScope.launch {
                            if (viewModel.skipLevelWithStars()) navController.popBackStack()
                        }
                    }
                },
                onWatchAdForLife = { onFinished ->
                    HapticsService.fire(HapticIntent.TAP)
                    AdsService.showRewarded(
                        activity,
                        AdPlacement.LEVELS_REWARDED_LIFE,
                        onReward = { coroutineScope.launch { viewModel.applyLifeReward() } },
                        onDismissed = { onFinished() },
                    )
                },
                onWatchAdToForgive = { onFinished ->
                    HapticsService.fire(HapticIntent.TAP)
                    AdsService.showRewarded(
                        activity,
                        AdPlacement.LEVELS_REWARDED_FORGIVE,
                        onReward = { coroutineScope.launch { viewModel.applyForgiveMistakesReward() } },
                        onDismissed = { onFinished() },
                    )
                },
                onWatchAdForHint = { onFinished ->
                    HapticsService.fire(HapticIntent.TAP)
                    AdsService.showRewarded(
                        activity,
                        AdPlacement.GAME_REWARDED_HINT,
                        onReward = {},
                        onDismissed = { rewarded ->
                            if (rewarded) {
                                viewModel.applyHintReward()
                                viewModel.resume()
                            }
                            onFinished()
                        },
                    )
                },
            )
        }

        composable(Routes.SETTINGS) {
            val ifResumed = rememberResumedGuard()
            val viewModel: SettingsViewModel = viewModel(factory = viewModelFactory { initializer { SettingsViewModel(container.prefs, container.notifications) } })
            val state by viewModel.state.collectAsState()
            val menuEntry = remember { navController.getBackStackEntry(Routes.MENU) }
            val menuViewModel: MenuViewModel = viewModel(viewModelStoreOwner = menuEntry, factory = viewModelFactory { initializer { MenuViewModel(container.boardCatalog, container.prefs) } })
            // The Settings row reopens the same full-screen What's New MainActivity presents
            // automatically after an upgrade; MainActivity owns the one presentation site so the
            // screen can sit above the whole nav graph, edge to edge. Reopening it manually
            // never writes whatsNewLastSeenVersion — see MainActivity.
            SettingsScreen(
                state,
                onBack = {
                    ifResumed {
                        if (state.difficultyChanged) menuViewModel.onSettingsDifficultyChanged()
                        navController.popBackStack()
                    }
                },
                onDifficulty = viewModel::setDifficulty,
                onTheme = viewModel::setTheme,
                onHaptics = viewModel::setHaptics,
                onEnableReminders = viewModel::enableReminders,
                onDisableReminders = viewModel::disableReminders,
                onWhatsNew = onWhatsNew,
                onAchievements = { ifResumed { navController.navigate(Routes.ACHIEVEMENTS) } },
                onDebugMenu = if (BuildConfig.DEBUG) { { ifResumed { navController.navigate(Routes.DEBUG_MENU) } } } else null,
            )
        }

        // Debug builds only, like iOS's `#if DEBUG` DebugMenuView: the route does not exist
        // in release, and nothing there can navigate to it.
        if (BuildConfig.DEBUG) {
            composable(Routes.DEBUG_MENU) {
                val ifResumed = rememberResumedGuard()
                DebugMenuScreen(
                    onBack = { ifResumed { navController.popBackStack() } },
                    onNotificationsAuthorized = { container.applicationScope.launch { container.notifications.activateReminders() } },
                    onRestoreLives = { container.levelLives.refill(LevelLivesService.MAX_LIVES) },
                )
            }
        }

        composable(Routes.ACHIEVEMENTS) {
            val ifResumed = rememberResumedGuard()
            val viewModel: AchievementsViewModel = viewModel(
                factory = viewModelFactory { initializer { AchievementsViewModel(container.profileStats) } },
            )
            val state by viewModel.state.collectAsState()
            AchievementsScreen(state = state, onBack = { ifResumed { navController.popBackStack() } })
        }

        composable(Routes.CREATE_MEMORAMA) {
            val ifResumed = rememberResumedGuard()
            val viewModel: CreateMemoramaViewModel = viewModel(
                factory = viewModelFactory {
                    initializer { CreateMemoramaViewModel(container.prefs) }
                },
            )
            // The same MenuViewModel instance still on the back stack — reused (not
            // recreated) so telling it about the new board lands on the view the player
            // returns to, rather than a throwaway second instance.
            val menuEntry = remember { navController.getBackStackEntry(Routes.MENU) }
            val menuViewModel: MenuViewModel = viewModel(
                viewModelStoreOwner = menuEntry,
                factory = viewModelFactory {
                    initializer { MenuViewModel(container.boardCatalog, container.prefs) }
                },
            )
            val state by viewModel.state.collectAsState()
            val coroutineScope = rememberCoroutineScope()
            CreateMemoramaScreen(
                state = state,
                onNameChange = viewModel::updateName,
                onEmojiInputChange = viewModel::updateEmojiInput,
                onAddEmoji = viewModel::addEmoji,
                onRemoveEmoji = viewModel::removeEmoji,
                onSave = {
                    ifResumed {
                        coroutineScope.launch {
                            if (viewModel.save()) {
                                menuViewModel.onCustomMemoramaChanged()
                                menuViewModel.showMyMemoramas()
                                navController.popBackStack()
                            }
                        }
                    }
                },
                onCancel = { ifResumed { navController.popBackStack() } },
            )
        }

        composable(
            route = Routes.GAME,
            arguments = listOf(
                navArgument("boardId") { type = NavType.StringType },
                navArgument("difficultyKey") { type = NavType.StringType },
            ),
        ) { backStackEntry ->
            val ifResumed = rememberResumedGuard()
            val boardId = backStackEntry.arguments?.getString("boardId").orEmpty()
            val difficulty = Difficulty.parseOrDefault(
                backStackEntry.arguments?.getString("difficultyKey"),
            )
            // The board comes from the same in-session repository the menu just read
            // from — free play never needs a second network round trip.
            val board = remember(boardId) { container.boardCatalog.board(boardId) }

            if (board == null) {
                // The board vanished between selection and this composition (e.g. a
                // custom board was deleted from another screen) — bounce back rather
                // than crash on a null board.
                LaunchedEffect(Unit) { navController.popBackStack() }
                return@composable
            }

            val viewModel: GameViewModel = viewModel(
                factory = viewModelFactory {
                    initializer {
                        GameViewModel(
                            board = board,
                            mode = GameMode.Free,
                            playerDifficulty = difficulty,
                            stats = UserPreferencesGameStatsRecorder(container.prefs),
                            profileStats = UserPreferencesProfileStatsRecorder(container.prefs),
                            statsScope = container.applicationScope,
                            onGameFinished = container.onGameFinished,
                            onCompletionInterstitial = { difficulty, durationMs ->
                                AdsService.notifyGameFinished(activity, difficulty, durationMs)
                            },
                            onHaptic = HapticsService::fire,
                            onGameWon = { container.reviews.recordSuccessfulAction(BuildConfig.VERSION_NAME) },
                            onAnalytics = AnalyticsService::log,
                            // Free play's two entry points (a board card, or the "random
                            // game" button) both navigate into this same route with no
                            // distinguishing state, so — unlike Levels/Seasons/Daily, each
                            // reached from exactly one place — this can't tell them apart
                            // the way iOS's separate `gameStartSource` literals
                            // ("menu_card"/"random_menu_button") do. Documented
                            // simplification, not a missed case: "menu_card" is the common
                            // path and is reported for both.
                            initialSource = "menu_card",
                        )
                    }
                },
            )
            val state by viewModel.state.collectAsState()
            GameScreen(
                state = state,
                onChoose = viewModel::choose,
                onPauseToggle = {
                    if (state.isPaused) viewModel.resume() else viewModel.pause()
                },
                onBackgrounded = viewModel::pauseForBackground,
                onQuit = {
                    ifResumed {
                        // Free play has no lose-screen rescue to protect, so this doubles as
                        // the mid-game abandon (mirrors iOS's `tapOnExit()`).
                        AnalyticsService.log(
                            AnalyticsEvent.QuitConfirmed(
                                difficulty = state.recordedDifficulty.key,
                                timeRemaining = state.timeRemaining.toInt(),
                                failedTries = state.failedTries,
                            ),
                        )
                        HapticsService.fire(HapticIntent.TAP)
                        navController.popBackStack()
                    }
                },
                onRetry = {
                    AnalyticsService.log(
                        AnalyticsEvent.RetryTapped(
                            difficulty = state.recordedDifficulty.key,
                            cardsCount = state.cards.size,
                            source = if (state.outcome != null) "lose_modal" else "pause_modal",
                        ),
                    )
                    HapticsService.fire(HapticIntent.TAP)
                    viewModel.restart()
                },
                onWatchAdForHint = { onFinished ->
                    HapticsService.fire(HapticIntent.TAP)
                    AdsService.showRewarded(
                        activity,
                        AdPlacement.GAME_REWARDED_HINT,
                        onReward = {},
                        onDismissed = { rewarded ->
                            if (rewarded) {
                                viewModel.applyHintReward()
                                viewModel.resume()
                            }
                            onFinished()
                        },
                    )
                },
            )
        }
    }
}

/**
 * Runs a navigation only while the screen asking for it is still the resumed one on top.
 *
 * A screen that is leaving is still drawn, and still takes taps, for its whole exit
 * transition. A second tap in that window navigated again: double-tapping a game's quit
 * "Accept" or "Back to levels" popped the Menu as well and left an empty back stack — a
 * blank screen the player could only escape by killing the app (QA DM-010) — and a
 * double-tapped board or level tile pushed two games. Navigating moves this screen's back
 * stack entry below RESUMED at once, so the guard drops every tap after the first.
 *
 * The same rule as lifecycle-compose's `dropUnlessResumed`, which only wraps callbacks that
 * take no arguments; several here take a board, level or season.
 */
@Composable
private fun rememberResumedGuard(): (() -> Unit) -> Unit {
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    return remember(lifecycle) {
        { action -> if (lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) action() }
    }
}
