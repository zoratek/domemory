//
//  MemorizeViewModel.swift
//  DoMemory
//
//  Created by Ezequiel Barreto on 24/09/20.
//

import SwiftUI
import Observation

/// What a MemorizeView instance is playing: a freely-picked board, today's
/// Daily Challenge, or a numbered level — endless Levels or a finite Season,
/// told apart by the `LevelContext`'s store rather than by a separate case.
enum GameMode: Equatable {
    case free
    case dailyChallenge
    case level(LevelContext)

    /// Hand-written because `LevelContext` carries a `LevelProgressStore`
    /// existential, which is not `Equatable` and so kills the synthesis the
    /// declaration used to get for free. `isDailyChallenge` below is written as
    /// `mode == .dailyChallenge` and would stop compiling without this.
    ///
    /// Two `.level` modes are the same game when they are the same numbered
    /// level of the same season (`nil` season being endless Levels). The store
    /// is identity, not value — comparing witnesses would make two equivalent
    /// contexts unequal for no useful reason.
    static func == (lhs: GameMode, rhs: GameMode) -> Bool {
        switch (lhs, rhs) {
        case (.free, .free), (.dailyChallenge, .dailyChallenge):
            return true
        case let (.level(lhsContext), .level(rhsContext)):
            return lhsContext.number == rhsContext.number
                && lhsContext.seasonID == rhsContext.seasonID
        default:
            return false
        }
    }
}

/// Why the current game ended in a loss. Drives which rescue the LoseModal
/// offers — extra time is useless when you busted the mistake budget.
enum LoseReason: Equatable {
    case outOfTime
    case tooManyMistakes
}

@Observable
@MainActor
class MemorizeViewModel {
    private(set) var model: MemoryGame<String> = MemorizeViewModel.createMemoryGame()
    var showPauseView: Bool = false
    var timeRemaining: Int = 0
    var showQuitView: Bool = false
    var showWinView: Bool = false
    var isRewardedAdInProgress: Bool = false

    var memorama: Memorama?
    private(set) var mode: GameMode
    var isDailyChallenge: Bool { mode == .dailyChallenge }
    var levelNumber: Int? {
        if case .level(let context) = mode { return context.number }
        return nil
    }
    /// The level being played, or nil outside level play. Everything that needs
    /// the *store* — boards, unlocks, stars, skip — goes through this;
    /// `levelNumber` stays the narrow value the views already read.
    private var levelContext: LevelContext? {
        if case .level(let context) = mode { return context }
        return nil
    }
    /// True when clearing the current board leads somewhere. Endless Levels
    /// always does; a finite season does not on its last level, and the win
    /// modal must not offer level 21 of a 20-level season.
    var hasNextLevel: Bool { levelContext?.nextLevelNumber != nil }
    private(set) var lastEarnedStars: Int = 0
    /// Lives left today for Levels mode; nil outside of level play.
    private(set) var levelLivesRemaining: Int?
    /// Spendable star balance, mirrored from StarWalletService so the view can
    /// observe it. Only meaningful during level play.
    private(set) var starBalance: Int = 0
    var showSkipLevelConfirm = false
    /// Set when the game has been lost; nil while it's still playable. Replaces
    /// the old `timeRemaining == 0` check so a second lose reason can exist.
    private(set) var loseReason: LoseReason? {
        didSet {
            // Only the transition into a loss is felt. This is also assigned
            // nil on every restart and rescue, which must stay silent.
            guard loseReason != nil, oldValue == nil else { return }
            HapticsService.shared.fire(.failure)
        }
    }
    var hasLost: Bool { loseReason != nil }
    /// Mistake budget for the current level; nil outside of level play.
    var maxFailures: Int? {
        guard let levelNumber else { return nil }
        return LevelCurve.maxFailures(for: levelNumber)
    }
    /// True in the last two mistakes of the budget, so the HUD can warn before
    /// the limit actually bites.
    var isNearFailureLimit: Bool {
        guard let maxFailures else { return false }
        return maxFailures - model.failedTries <= 2
    }
    var canWatchAdForLife: Bool {
        AdsService.shared.isRewardedConfigured(for: .levelsRewardedLife)
    }
    var closeView: Bool = false
    var shouldShowPie: Bool!

    private var timerTask: Task<Void, Never>?
    private var flipBackTask: Task<Void, Never>?
    private var hideMatchedTask: Task<Void, Never>?
    private var peekTask: Task<Void, Never>?
    private var mistakeLossTask: Task<Void, Never>?
    /// While set and in the future, the countdown holds. Kept as a deadline
    /// rather than cancelling `timerTask`, so freezing doesn't tear down the
    /// card flip-back scheduling the way `stopTimer()` would.
    private var frozenUntil: Date? {
        didSet {
            isFrozen = frozenUntil != nil
            if frozenUntil == nil { heldFreezeRemaining = nil }
        }
    }
    /// Freeze time left when the clock stopped, restored by `startTimer()`.
    /// `frozenUntil` is wall-clock, so without this a pause during Freeze would
    /// burn the Freeze the player paid for.
    private var heldFreezeRemaining: TimeInterval?
    /// True while a bought Peek is showing the board; the Peek button stays
    /// disabled until it ends.
    private(set) var isPeeking = false
    /// Mirrors `frozenUntil` for the HUD. A separate observable flag rather than
    /// a computed property because nothing else changes while the clock is held
    /// — `timeRemaining` stops ticking — so the view would have no signal to
    /// re-render when the freeze starts or expires.
    private(set) var isFrozen = false
    private var hasLoggedGameFinished = false
    /// Star power-ups bought during the current attempt, reported on
    /// `levelFinished`. Reset with every start, retry and next level.
    private var powerUpsUsedThisAttempt = 0
    private var gameStartedAt: Date?
    private var lastRewardedAdDate: Date?

    var canOfferRewardedAds: Bool {
        AdsService.shared.isRewardedConfigured(for: .gameRewardedExtraTime)
            || AdsService.shared.isRewardedConfigured(for: .gameRewardedHint)
    }

    init(memorama: Memorama?, mode: GameMode = .free) {
        self.memorama = memorama
        self.mode = mode
        if case .level = mode {
            self.levelLivesRemaining = LevelLivesService.shared.livesRemaining()
            self.starBalance = StarWalletService.shared.balance
        }
        guard let auxMemorama = memorama else { return }
        if auxMemorama.isDoubleItem {
            self.model = MemoryGame<String>(numbersOfPairsOfCards: auxMemorama.items.count) { partIndex in
                return auxMemorama.items[partIndex]
            }
        } else {
            self.model = MemoryGame<String>(numbersOfCards: auxMemorama.items.count) { partIndex in
                return auxMemorama.items[partIndex]
            }
        }
        self.shouldShowPie = shouldShowPieByDifficulty()
    }

    convenience init(memorama: Memorama?, isDailyChallenge: Bool) {
        self.init(memorama: memorama, mode: isDailyChallenge ? .dailyChallenge : .free)
    }

    /// Endless Levels. Kept at its original signature so `LevelsView`'s call
    /// site is unaffected by the store refactor.
    convenience init(level: Int) {
        self.init(context: LevelContext(number: level))
    }

    /// Any numbered level, endless or seasonal. The board comes from whichever
    /// store the context carries.
    convenience init(context: LevelContext) {
        self.init(memorama: context.board(), mode: .level(context))
    }

    private static func createMemoryGame() -> MemoryGame<String> {
        return MemoryGame<String>()
    }

    // MARK: - Access the model
    var cards: Array<MemoryGame<String>.Card> {
        model.cards
    }

    var failedTries: Int {
        model.failedTries
    }

    var difficultyDisplayTitle: String {
        switch gameDifficulty() {
        case .easy: return Strings.easy
        case .medium: return Strings.medium
        case .hard: return Strings.hard
        case .veryHard: return Strings.veryHard
        }
    }

    var dailyChallengeStreak: Int {
        isDailyChallenge ? DailyChallengeService.shared.currentStreak : 0
    }

    func getRemainingTime() -> Int {
        if let levelNumber {
            return LevelCurve.seconds(for: levelNumber)
        }
        let difficulty = getDifficulty()
        switch difficulty {
        case .easy: return 110
        case .medium: return 60
        case .hard: return 60
        case .veryHard: return 70
        }
    }

    func getPieRemainingTime() -> Int {
        0
    }

    func getIfAllAreMatched() {
        let count = model.cards.count
        let matchedCount = self.model.cards.filter { $0.isMatched }
        // Called on every tap, so the win only counts on the transition.
        let wasShowing = showWinView
        showWinView = count == matchedCount.count
        if showWinView {
            if !wasShowing {
                HapticsService.shared.fire(.success)
            }
            logGameFinishedIfNeeded(result: "win")
        }
    }

    // MARK: - Intent(s)
    func choose(card: MemoryGame<String>.Card) {
        flipBackTask?.cancel()
        flipBackTask = nil
        // MemoryGame.choose is a value-type mutation that reports nothing, so
        // the outcome is read from the state either side of it rather than
        // changing the pure model's signature.
        let failuresBefore = model.failedTries
        let matchedBefore = model.cards.filter(\.isMatched).count
        let faceUpBefore = model.cards.filter(\.isFaceUp).count
        model.choose(card: card)
        fireChooseHaptic(
            failuresBefore: failuresBefore,
            matchedBefore: matchedBefore,
            faceUpBefore: faceUpBefore
        )
        if AnalyticsService.shouldSample(AnalyticsService.cardTapSampleRate) {
            AnalyticsService.log(
                .cardTapped(
                    difficulty: gameDifficulty().rawValue,
                    cardsCount: model.cards.count,
                    failedTries: model.failedTries
                )
            )
        }
        scheduleFlipBackIfNeeded()
        scheduleMatchedHideIfNeeded()
        scheduleMistakeLossIfNeeded()
    }

    private func fireChooseHaptic(failuresBefore: Int, matchedBefore: Int, faceUpBefore: Int) {
        let matchedNow = model.cards.filter(\.isMatched).count
        // MemoryGame.choose ignores taps on cards that are already face-up or
        // already matched — both reachable, since the mismatched pair stays
        // tappable for the 2s flip-back delay. Nothing moved, so nothing is
        // felt; otherwise a dead tap buzzes as though a card turned over.
        guard model.failedTries > failuresBefore
                || matchedNow > matchedBefore
                || model.cards.filter(\.isFaceUp).count != faceUpBefore else { return }

        if model.failedTries > failuresBefore {
            HapticsService.shared.fire(.mismatch)
        } else if matchedNow > matchedBefore {
            // The final pair is followed within milliseconds by the win
            // pattern from getIfAllAreMatched. A thud in front of it reads as
            // a stutter, so the win is left to speak for itself.
            if matchedNow < model.cards.count {
                HapticsService.shared.fire(.match)
            }
        } else {
            HapticsService.shared.fire(.cardFlip)
        }
        // The next tap is almost always another card.
        HapticsService.shared.prepare(for: .cardFlip)
    }

    /// Ends the level once the mistake budget is spent. Deferred briefly so the
    /// player sees the mismatched pair that finished them off instead of having
    /// the modal slam over it.
    private func scheduleMistakeLossIfNeeded() {
        guard let maxFailures, loseReason == nil, mistakeLossTask == nil else { return }
        guard model.failedTries >= maxFailures else { return }
        mistakeLossTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(0.8))
            guard !Task.isCancelled, let self else { return }
            self.mistakeLossTask = nil
            // The clock can reach zero inside the delay above. Whichever
            // failure landed first is the real one, so never overwrite it —
            // otherwise a timeout would be offered the mistake rescue.
            guard self.loseReason == nil else { return }
            self.stopTimer()
            self.loseReason = .tooManyMistakes
            if let levelNumber = self.levelNumber {
                AnalyticsService.log(
                    .levelFailedByMistakes(
                        level: levelNumber,
                        maxFailures: maxFailures,
                        timeRemaining: self.timeRemaining
                    )
                )
            }
        }
    }

    private func scheduleFlipBackIfNeeded() {
        let faceUpUnmatched = model.cards.filter { $0.isFaceUp && !$0.isMatched }
        guard faceUpUnmatched.count == 2 else { return }
        flipBackTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.5)) {
                self?.model.flipBackUnmatchedCards()
            }
        }
    }

    private func scheduleMatchedHideIfNeeded() {
        let faceUpMatched = model.cards.filter { $0.isFaceUp && $0.isMatched }
        guard !faceUpMatched.isEmpty else { return }
        hideMatchedTask?.cancel()
        hideMatchedTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.35)) {
                self?.model.hideMatchedFaceUpCards()
            }
            self?.getIfAllAreMatched()
        }
    }

    func resetGame() {
        guard let auxMemorama = memorama else { return }
        model = MemoryGame<String>(numbersOfPairsOfCards: auxMemorama.items.count) { partIndex in
            return auxMemorama.items[partIndex]
        }
    }

    // MARK: - Timer
    func startTimer() {
        stopTimer()
        if let held = heldFreezeRemaining {
            frozenUntil = held > 0 ? Date().addingTimeInterval(held) : nil
            heldFreezeRemaining = nil
        }
        HapticsService.shared.prepare(for: .cardFlip)
        timerTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled, self.timeRemaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                if let frozenUntil = self.frozenUntil {
                    guard Date() >= frozenUntil else { continue }
                    self.frozenUntil = nil
                    // The clock restarting is easy to miss visually.
                    HapticsService.shared.fire(.select)
                }
                if self.timeRemaining > 0 {
                    self.timeRemaining -= 1
                }
                if self.timeRemaining == 0, self.loseReason == nil {
                    self.loseReason = .outOfTime
                }
            }
        }
        // stopTimer() above cancelled any pending mistake loss; re-arm it so
        // pausing mid-delay can't be used to play on past the budget.
        scheduleMistakeLossIfNeeded()
    }

    func stopTimer() {
        // Only the first stop holds the freeze: a second one while still
        // stopped would read a deadline that kept running in the meantime.
        if let frozenUntil, heldFreezeRemaining == nil {
            heldFreezeRemaining = max(0, frozenUntil.timeIntervalSinceNow)
        }
        timerTask?.cancel()
        timerTask = nil
        flipBackTask?.cancel()
        flipBackTask = nil
        hideMatchedTask?.cancel()
        hideMatchedTask = nil
        mistakeLossTask?.cancel()
        mistakeLossTask = nil
        endPeekIfActive()
    }

    /// Ends an in-flight Peek, flipping the board back. Without this, pausing
    /// during a peek would cancel the scheduled flip-back and leave every card
    /// revealed for free.
    private func endPeekIfActive() {
        guard peekTask != nil else { return }
        peekTask?.cancel()
        peekTask = nil
        isPeeking = false
        model.flipBackUnmatchedCards()
    }

    func reconnectTime() {
        startTimer()
    }

    func trackGameStarted(source: String) {
        hasLoggedGameFinished = false
        powerUpsUsedThisAttempt = 0
        gameStartedAt = Date()
        Task { @MainActor in
            AdsService.shared.loadInterstitial(for: .gameFinishedInterstitial)
            AdsService.shared.loadRewardedAd(for: .gameRewardedExtraTime)
            AdsService.shared.loadRewardedAd(for: .gameRewardedHint)
            if case .level = mode {
                AdsService.shared.loadRewardedAd(for: .levelsRewardedLife)
                AdsService.shared.loadRewardedAd(for: .levelsRewardedForgive)
            }
        }
        AnalyticsService.log(
            .gameStarted(
                source: source,
                difficulty: gameDifficulty().rawValue,
                cardsCount: model.cards.count,
                isCustom: memorama?.id.hasPrefix("custom_") ?? false
            )
        )
        if isDailyChallenge {
            AnalyticsService.log(.dailyChallengeStarted(streak: DailyChallengeService.shared.currentStreak))
        }
        if let context = levelContext {
            // One event for both modes, separated by the seasonID dimension
            // rather than by a parallel season event set, so the two funnels
            // stay directly comparable.
            AnalyticsService.log(.levelStarted(level: context.number, seasonID: context.seasonID))
        }
    }

    func tapOnPause() {
        HapticsService.shared.fire(.tap)
        stopTimer()
        showPauseView.toggle()
        AnalyticsService.log(
            .pauseOpened(
                difficulty: gameDifficulty().rawValue,
                timeRemaining: timeRemaining
            )
        )
    }

    func tapOnQuitPrompt() {
        HapticsService.shared.fire(.tap)
        stopTimer()
        showQuitView.toggle()
    }

    /// - Parameter allowInterstitial: pass `false` when the player has just
    ///   paid for the outcome. Charging 15★ to skip a level and then serving an
    ///   ad on the way out is the worst moment in the app to show one.
    private func logGameFinishedIfNeeded(result: String, allowInterstitial: Bool = true) {
        guard !hasLoggedGameFinished else { return }
        hasLoggedGameFinished = true
        let didWin = result == "win"
        if let memoramaID = memorama?.id {
            GameStatsService.shared.recordGameFinished(memoramaID: memoramaID, didWin: didWin)
        }
        ProfileStatsService.shared.recordGameFinished(
            didWin: didWin,
            isPerfect: didWin && model.failedTries == 0,
            difficulty: gameDifficulty(),
            timeRemaining: timeRemaining
        )
        if isDailyChallenge {
            let streak = DailyChallengeService.shared.recordCompletion(didWin: didWin)
            AnalyticsService.log(.dailyChallengeFinished(result: result, streak: streak))
            if didWin, [3, 7, 14, 30, 100].contains(streak) {
                AnalyticsService.log(.streakMilestone(days: streak))
            }
            NotificationService.shared.refreshStreakAtRiskReminder()
        }
        if let context = levelContext {
            let levelNumber = context.number
            // Endless Levels or a season, whichever owns this level's progress.
            let progressService = context.store
            let alreadyUnlockedNext = progressService.isUnlocked(levelNumber + 1)
            let earnedStars = progressService.recordCompletion(
                level: levelNumber,
                didWin: didWin,
                timeRemaining: timeRemaining,
                totalTime: getRemainingTime(),
                failedTries: model.failedTries
            )
            lastEarnedStars = earnedStars
            starBalance = StarWalletService.shared.balance
            AnalyticsService.log(
                .levelFinished(
                    level: levelNumber,
                    result: result,
                    stars: earnedStars,
                    powerUpsUsed: powerUpsUsedThisAttempt,
                    seasonID: context.seasonID
                )
            )
            // `levelUnlocked` means "a new playable level became available", so
            // it is gated on there actually being one. `recordCompletion` marks
            // a finished season by storing `levelCount + 1` as its highest
            // unlocked level, and logging that number would emit one unlock for
            // a level that does not exist on every completed season — an
            // unlocks-per-season funnel would overcount by exactly one, and the
            // seasonID dimension only makes that filterable if you already know
            // to filter it. Nothing is lost: completion stays derivable from
            // `levelFinished` with `level == levelCount` and a seasonID.
            // `nextLevelNumber` is the ceiling Phase 2 already established and
            // is never nil for endless Levels, which is therefore unaffected.
            if didWin, !alreadyUnlockedNext, let unlockedLevel = context.nextLevelNumber {
                AnalyticsService.log(.levelUnlocked(level: unlockedLevel, seasonID: context.seasonID))
            }
            if !didWin {
                // `consumeLife` also returns 0 when there was nothing to spend;
                // only a real 1 → 0 transition is a depletion.
                let hadLives = LevelLivesService.shared.hasLivesRemaining()
                let remaining = LevelLivesService.shared.consumeLife()
                levelLivesRemaining = remaining
                AnalyticsService.log(.levelLifeConsumed(livesRemaining: remaining))
                if hadLives, remaining == 0 {
                    AnalyticsService.log(.levelLivesDepleted(level: levelNumber, seasonID: context.seasonID))
                }
            }
        }
        NotificationService.shared.scheduleInactivityReminder()
        LeaderboardService.shared.syncAfterGame()
        AnalyticsService.log(
            .gameFinished(
                result: result,
                difficulty: gameDifficulty().rawValue,
                cardsCount: model.cards.count,
                failedTries: model.failedTries,
                timeRemaining: timeRemaining,
                isCustom: memorama?.id.hasPrefix("custom_") ?? false
            )
        )
        if allowInterstitial, shouldPresentCompletionInterstitial {
            let frequency = interstitialFrequency()
            Task { @MainActor in
                AdsService.shared.presentInterstitialEvery(frequency, for: .gameFinishedInterstitial)
            }
        }
    }
}

extension MemorizeViewModel {
    private func restartGame() {
        self.showPauseView = false
        self.resetGame()
        self.frozenUntil = nil
        self.loseReason = nil
        self.starBalance = StarWalletService.shared.balance
        self.timeRemaining = getRemainingTime()
        startTimer()
        trackGameStarted(source: "retry")
    }

    private func getDifficulty() -> Difficulty {
        guard let userSettings = UserManageObject().getUserSettings() else { return .medium }
        return Difficulty(rawValue: userSettings.dificulty ?? "medium") ?? .medium
    }

    private func gameDifficulty() -> Difficulty {
        if let memoramaDifficulty = memorama?.difficulty, let parsed = Difficulty(rawValue: memoramaDifficulty) {
            return parsed
        }
        return getDifficulty()
    }

    private func shouldShowPieByDifficulty() -> Bool {
        if let levelNumber {
            return levelNumber >= 25
        }
        let difficulty = getDifficulty()
        switch difficulty {
        case .easy: return false
        case .medium: return false
        case .hard: return true
        case .veryHard: return true
        }
    }

    /// Swaps in the next level's board in place (no navigation), with a fresh
    /// timer and card layout. Only valid when currently playing a level that
    /// has a successor: a finite season stops at `levelCount`, and this is the
    /// backstop for that even if a caller offers the action anyway.
    fileprivate func advanceToNextLevel() {
        // A season whose last level was just cleared has no `nextLevelNumber`
        // and bails here, leaving the win modal up with its primary action
        // pointing back at the map. No completion reward is granted; that is
        // deliberately out of scope, and this guard is where one would hook in.
        guard let context = levelContext, let nextLevel = context.nextLevelNumber else { return }
        let nextContext = context.advanced(to: nextLevel)
        mode = .level(nextContext)
        memorama = nextContext.board()
        levelLivesRemaining = LevelLivesService.shared.livesRemaining()
        starBalance = StarWalletService.shared.balance
        frozenUntil = nil
        loseReason = nil
        resetGame()
        shouldShowPie = shouldShowPieByDifficulty()
        showWinView = false
        timeRemaining = getRemainingTime()
        startTimer()
        trackGameStarted(source: "next_level")
    }

    private var shouldPresentCompletionInterstitial: Bool {
        guard let gameStartedAt else { return false }
        guard Date().timeIntervalSince(gameStartedAt) >= 20 else { return false }
        if let lastRewardedAdDate,
           Date().timeIntervalSince(lastRewardedAdDate) < 60 {
            return false
        }
        return true
    }

    private func interstitialFrequency() -> Int {
        switch gameDifficulty() {
        case .easy, .medium: return 3
        case .hard, .veryHard: return 2
        }
    }

    private func presentRewardedAd(for placement: AdPlacement, reward: @escaping () -> Void) {
        guard !isRewardedAdInProgress else { return }
        isRewardedAdInProgress = true
        AnalyticsService.log(.adLifecycle(placement: placement.rawValue, action: "requested"))
        AdsService.shared.presentRewardedAd(
            for: placement,
            rewardHandler: { [weak self] in
                guard let self else { return }
                self.lastRewardedAdDate = Date()
                AnalyticsService.log(.adLifecycle(placement: placement.rawValue, action: "reward_earned"))
                HapticsService.shared.fire(.reward)
                reward()
            },
            completion: { [weak self] didEarnReward in
                guard let self else { return }
                self.isRewardedAdInProgress = false
                AnalyticsService.log(.adLifecycle(placement: placement.rawValue, action: didEarnReward ? "dismissed_rewarded" : "dismissed_unrewarded"))
            }
        )
    }

    private func revealHintPair() {
        guard model.revealUnmatchedPairForHint() else { return }
        scheduleFlipBackIfNeeded()
    }
}

// MARK: - Star power-ups
extension MemorizeViewModel {
    /// Power-ups are a Levels-mode feature: stars are earned there, so they're
    /// spent there too.
    var canUsePowerUps: Bool { levelNumber != nil }

    func canAfford(_ powerUp: LevelPowerUp) -> Bool {
        starBalance >= powerUp.cost
    }

    /// Peek or Freeze already running. Buying either again restarts it rather
    /// than extending it, so it would charge twice for what plays as one.
    func isActive(_ powerUp: LevelPowerUp) -> Bool {
        switch powerUp {
        case .peek: isPeeking
        case .freeze: isFrozen
        case .extraTime, .revealPair: false
        }
    }

    /// Buys and immediately applies a power-up. No confirmation step — costs
    /// are small and the clock is running, so a modal here would cost more than
    /// a misfire does.
    func use(_ powerUp: LevelPowerUp) {
        guard let levelNumber, canAfford(powerUp), !isActive(powerUp) else { return }
        guard StarWalletService.shared.spend(powerUp.cost) else { return }
        HapticsService.shared.fire(.reward)
        starBalance = StarWalletService.shared.balance

        switch powerUp {
        case .extraTime:
            timeRemaining += LevelPowerUp.extraTimeSeconds
        case .peek:
            startPeek()
        case .freeze:
            frozenUntil = Date().addingTimeInterval(LevelPowerUp.freezeDuration)
        case .revealPair:
            revealHintPair()
        }

        powerUpsUsedThisAttempt += 1
        AnalyticsService.log(
            .levelPowerUpUsed(
                powerUp: powerUp.rawValue,
                level: levelNumber,
                cost: powerUp.cost,
                balanceAfter: starBalance,
                seasonID: levelContext?.seasonID
            )
        )
    }

    private func startPeek() {
        peekTask?.cancel()
        flipBackTask?.cancel()
        flipBackTask = nil
        withAnimation(.easeInOut(duration: 0.3)) {
            model.revealAllUnmatchedForPeek()
        }
        isPeeking = true
        peekTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(LevelPowerUp.peekDuration))
            guard !Task.isCancelled, let self else { return }
            self.peekTask = nil
            self.isPeeking = false
            withAnimation(.easeInOut(duration: 0.4)) {
                self.model.flipBackUnmatchedCards()
            }
        }
    }
}

// MARK: - Star purchases from the lose modal
extension MemorizeViewModel {
    /// Not gated on the Remove-Ads entitlement: purchasers spend lives like
    /// everyone else, and Remove Ads suppresses involuntary advertising only,
    /// so both top-ups — this and the rewarded ad — stay open to them.
    var canBuyLifeWithStars: Bool {
        levelNumber != nil && starBalance >= LevelPowerUp.lifeCost
    }

    /// True while the lose modal is up and the loss has not been booked yet.
    /// The life is only spent when the player leaves the loss behind — Try
    /// again, Menu or Skip — so a rescue (forgive, +30s) still keeps it.
    var isLifeAtStake: Bool {
        levelNumber != nil && hasLost && !hasLoggedGameFinished && (levelLivesRemaining ?? 0) > 0
    }

    /// Skipping books the loss and returns to the map, whose lives gate then
    /// decides whether the unlocked level is playable. When the skip would
    /// leave no life — the player is already out, or it would spend their
    /// last — it sells an unlock they can't use today, so it isn't offered.
    var canSkipLevelWithStars: Bool {
        guard levelNumber != nil, starBalance >= LevelPowerUp.skipLevelCost else { return false }
        let livesAfterSkip = (levelLivesRemaining ?? 0) - (isLifeAtStake ? 1 : 0)
        return livesAfterSkip > 0
    }

    func tapOnBuyLifeWithStars() {
        guard canBuyLifeWithStars else { return }
        guard StarWalletService.shared.spend(LevelPowerUp.lifeCost) else { return }
        HapticsService.shared.fire(.reward)
        starBalance = StarWalletService.shared.balance
        levelLivesRemaining = LevelLivesService.shared.addLife()
        AnalyticsService.log(
            .levelLifePurchasedWithStars(cost: LevelPowerUp.lifeCost, balanceAfter: starBalance)
        )
        restartGame()
    }

    var canForgiveWithStars: Bool {
        levelNumber != nil && starBalance >= LevelPowerUp.forgiveCost
    }

    var canWatchAdToForgive: Bool {
        AdsService.shared.isRewardedConfigured(for: .levelsRewardedForgive)
    }

    func tapOnWatchAdToForgive() {
        HapticsService.shared.fire(.tap)
        presentRewardedAd(for: .levelsRewardedForgive) { [weak self] in
            self?.forgiveMistakes(LevelPowerUp.forgiveAmount, source: "ad")
        }
    }

    func tapOnForgiveWithStars() {
        guard canForgiveWithStars else { return }
        guard StarWalletService.shared.spend(LevelPowerUp.forgiveCost) else { return }
        HapticsService.shared.fire(.reward)
        starBalance = StarWalletService.shared.balance
        forgiveMistakes(LevelPowerUp.forgiveAmount, source: "stars")
    }

    /// Refunds mistakes and resumes the *same* board — matched pairs stay
    /// matched. Deliberately does not call `logGameFinishedIfNeeded`: the game
    /// isn't over, and recording it would consume a life and log a loss.
    private func forgiveMistakes(_ count: Int, source: String) {
        guard let levelNumber else { return }
        model.forgiveFailures(count)
        loseReason = nil
        // Guarantee a playable clock. `startTimer()`'s loop exits immediately
        // when `timeRemaining` is already 0, which would resume the board with
        // a permanently frozen countdown and no way to lose.
        timeRemaining = max(timeRemaining, LevelPowerUp.forgiveMinimumSeconds)
        startTimer()
        AnalyticsService.log(
            .levelMistakesForgiven(level: levelNumber, amount: count, source: source)
        )
    }

    func tapOnSkipLevelPrompt() {
        HapticsService.shared.fire(.tap)
        showSkipLevelConfirm = true
    }

    func tapOnCancelSkipLevel() {
        HapticsService.shared.fire(.tap)
        showSkipLevelConfirm = false
    }

    func tapOnConfirmSkipLevel() {
        guard let context = levelContext, canSkipLevelWithStars else { return }
        let levelNumber = context.number
        guard StarWalletService.shared.spend(LevelPowerUp.skipLevelCost) else { return }
        HapticsService.shared.fire(.reward)
        starBalance = StarWalletService.shared.balance
        showSkipLevelConfirm = false
        // The attempt still counts as a loss — skipping buys the unlock, not a
        // clean record. Idempotent, so this is a no-op if it already fired.
        logGameFinishedIfNeeded(result: "lose", allowInterstitial: false)
        context.store.skipLevel(levelNumber)
        AnalyticsService.log(
            .levelSkipped(level: levelNumber, cost: LevelPowerUp.skipLevelCost, balanceAfter: starBalance)
        )
        // Same ceiling as the win path: buying the skip on a season's final
        // level completes the season, it does not make a level 21 playable.
        if let unlockedLevel = context.nextLevelNumber {
            AnalyticsService.log(.levelUnlocked(level: unlockedLevel, seasonID: context.seasonID))
        }
        // Return to the map rather than auto-starting the next level, so the
        // lives gate there still decides whether they can play on.
        closeView = true
    }
}

// MARK: LISTENERS
extension MemorizeViewModel: PauseModalListener {
    func tapOnGoHome() {
        HapticsService.shared.fire(.tap)

    }

    func tapOnResumeGame() {
        HapticsService.shared.fire(.tap)
        self.showPauseView = false
        AnalyticsService.log(
            .resumeTapped(
                difficulty: gameDifficulty().rawValue,
                timeRemaining: timeRemaining
            )
        )
        startTimer()
    }

    func tapOnReloadGame() {
        HapticsService.shared.fire(.tap)
        AnalyticsService.log(
            .retryTapped(
                difficulty: gameDifficulty().rawValue,
                cardsCount: model.cards.count,
                source: "pause_modal"
            )
        )
        restartGame()
    }

    func tapOnRewardedHint() {
        HapticsService.shared.fire(.tap)
        presentRewardedAd(for: .gameRewardedHint) { [weak self] in
            guard let self else { return }
            self.showPauseView = false
            self.revealHintPair()
            self.startTimer()
        }
    }
}

extension MemorizeViewModel: LoseModalViewModelListener {
    func tapOnTryAgain() {
        HapticsService.shared.fire(.tap)
        logGameFinishedIfNeeded(result: "lose")
        AnalyticsService.log(
            .retryTapped(
                difficulty: gameDifficulty().rawValue,
                cardsCount: model.cards.count,
                source: "lose_modal"
            )
        )
        guard levelNumber == nil || LevelLivesService.shared.hasLivesRemaining() else {
            // Out of lives: stay on LoseModal, which re-renders into its
            // out-of-lives state now that levelLivesRemaining is 0.
            return
        }
        restartGame()
    }

    func tapOnGoToMenuAfterLose() {
        HapticsService.shared.fire(.tap)
        logGameFinishedIfNeeded(result: "lose")
        closeView = true
    }

    func tapOnRewardedExtraTime() {
        HapticsService.shared.fire(.tap)
        presentRewardedAd(for: .gameRewardedExtraTime) { [weak self] in
            guard let self else { return }
            self.timeRemaining = max(self.timeRemaining, 0) + 30
            // The modal is driven by `loseReason` now, not by the clock, so
            // adding time alone would leave it on screen.
            self.loseReason = nil
            self.startTimer()
        }
    }

    func tapOnWatchAdForLife() {
        HapticsService.shared.fire(.tap)
        presentRewardedAd(for: .levelsRewardedLife) { [weak self] in
            guard let self else { return }
            let updated = LevelLivesService.shared.addLife()
            self.levelLivesRemaining = updated
            AnalyticsService.log(.levelLifeGrantedFromAd(livesRemaining: updated))
            self.restartGame()
        }
    }
}

extension MemorizeViewModel: QuitModalListener {
    func tapOnCancel() {
        HapticsService.shared.fire(.tap)
        self.showQuitView = false
        self.closeView = false
    }

    func tapOnExit() {
        HapticsService.shared.fire(.tap)
        self.showQuitView = false
        self.closeView = true
        AnalyticsService.log(
            .quitConfirmed(
                difficulty: gameDifficulty().rawValue,
                timeRemaining: timeRemaining,
                failedTries: model.failedTries
            )
        )
    }
}

extension MemorizeViewModel: WinModalListener {
    func tapOnContinue() {
        HapticsService.shared.fire(.tap)
        self.showWinView = false
        self.closeView = true
        AppReviews.recordSuccessfulGameWin()
    }

    func tapOnNextLevel() {
        HapticsService.shared.fire(.tap)
        advanceToNextLevel()
    }
}
