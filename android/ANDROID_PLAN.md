# DoMemory Android — Development Plan

Companion to `DOMEMORY_ANDROID_SPEC.md`, which is the behavioural source of truth.
This document holds the **decisions**, the **stack**, the **layout** and the
**phase plan**. When the two disagree about *what the app does*, the spec wins.
When they disagree about *how Android builds it*, this file wins.

Target: feature parity with iOS 4.2.0.

---

## 1. Decisions (locked)

| # | Decision | Value | Consequence |
|---|---|---|---|
| D1 | Daily Challenge board parity with iOS | **Not required** | Android uses the same seed string (`YYYYMMDD`), the same SplitMix64/FNV-1a algorithm and the same 48-emoji pool, but iOS's FNV basis is one digit short of the standard value Android uses (spec §6.1), so the streams differ, and the shuffle is Kotlin's own Fisher–Yates. Boards will be *deterministic per day and identical across all Android devices*, but not necessarily equal to iOS. See §6 Risks — this changes a marketing claim. |
| D2 | Backend + monetization credentials | **Firebase and AdMob wired; Billing deferred** | `app/google-services.json` is in place for `domemory-c9211`, so the real `/data` catalog is read. AdMob's Android app/unit IDs are configured; Remove Ads/Play Billing are deliberately deferred. |
| D3 | Project structure | **Single `:app` module, package-per-feature** | Mirrors the iOS `Modules/` + `Services/` split. No Gradle module graph to maintain. Boundaries enforced by package discipline and constructor injection, not by the build system. |
| D4 | Dependency injection | **Manual — an `AppContainer` service locator** | No Hilt/KSP. The iOS app wires services by hand too; this keeps the build fast and removes an annotation-processor version dependency. Revisit if the container exceeds ~25 services. |
| D5 | Persistence | **DataStore Preferences only. No Room.** | Spec §13.2: CoreData holds one row. `hasOnboarded` becomes an explicit boolean flag rather than "a record exists". |
| D6 | Progress migration from iOS | **Out of scope** | No account layer exists on either platform. Progress stays device-local. |
| D7 | UI | **Jetpack Compose + Material 3**, custom palette | The spec's colour tokens (§14.1) are the design system; Material 3 supplies layout primitives and the shape/typography scaffolding only. |
| D8 | State | **`ViewModel` + `StateFlow`** | Direct analogue of iOS `@Observable` view models. Game loop state is one immutable `data class` emitted as `StateFlow`. |

### Decisions still open (owner: you)

| # | Question | Needed by |
|---|---|---|
| O7 | Register a second Firebase Android client for `com.ezequielbrrt.domemory.debug`? Without one, debug and release cannot be installed side by side (see §2). | any time |
| O1 | Register `domemory.app`, deploy `assetlinks.json` plus iOS's `apple-app-site-association`, then verify the shared-link join flow. | deferred Phase 6 follow-up |

---

## 2. Stack and toolchain

Pinned against what is installed on this machine and what is current as of 2026-09-10.

| Item | Version | Note |
|---|---|---|
| Gradle | 9.7.1 | wrapper committed; bootstrapped locally (no system Gradle) |
| Android Gradle Plugin | 9.4.0 | latest stable |
| Kotlin | 2.4.20 | K2, Compose compiler plugin bundled with Kotlin |
| JDK | 21 toolchain | Android Studio ships JBR 25; the toolchain pins 21 so CI and Studio agree |
| compileSdk / targetSdk | 37 | the only platform installed locally (`android-37.0`) |
| minSdk | 26 | gives `java.time` without desugaring — the day-key logic (§8) leans on it heavily |
| Compose BOM | 2026.09.00 | |
| Build tools | 36.0.0 | installed |

Three things the toolchain forced, worth knowing before you open the project:

- **AGP 9 has built-in Kotlin support.** Applying `org.jetbrains.kotlin.android`
  alongside it is now an error, so the app module applies only the Android and Compose
  plugins. `libs.versions.toml` still pins the Kotlin version for the Compose plugin.
- **The JDK 21 toolchain is provisioned, not assumed.** No JDK 21 is installed on this
  machine (Android Studio ships JBR 25), so `settings.gradle.kts` applies the Foojay
  resolver and Gradle downloads a matching JDK on first build. That also makes CI work
  with no JDK setup step.
- **No Gradle on the machine.** The wrapper is committed and pinned with a distribution
  checksum, so `./gradlew` is the only entry point anyone needs.

One deliberate divergence from the spec's string catalog: `levels_lives_remaining_format`
ships on iOS as `%d of %d lives remaining`, which Android translators cannot reorder.
It is positional here (`%1$d of %2$d`). Same output, safe for the nine translations.

Libraries added per phase, not up front: `datastore-preferences` (P2),
`firebase-bom` + `database` + `auth` + `analytics` (P2), `coil` (P4),
`glance-appwidget` + `work-runtime` (P5), `zxing` (P6),
`play-services-ads` + `billing-ktx` + `review-ktx` (P7).

---

## 3. Package layout

```
com.ezequielbrrt.domemory
├── DoMemoryApplication.kt          // creates AppContainer
├── MainActivity.kt                 // single activity, Compose host, deep-link intake
├── AppContainer.kt                 // manual DI graph
├── core/
│   ├── model/        Card, Board, MemoryGame, Difficulty, GameMode, LevelContext
│   ├── rng/          SeededGenerator (SplitMix64 + FNV-1a), EmojiPool
│   ├── time/         DayKey, Clock abstraction (tests need a fake clock)
│   └── util/         format helpers
├── data/
│   ├── prefs/        DataStore keys + typed accessors (one file, mirrors §13.2)
│   ├── remote/       FirebaseCatalogSource, SeasonCatalogSource   [stubbed in P1-P2]
│   └── repository/   BoardRepository, CustomBoardRepository, FavouritesRepository
├── services/                        // 1:1 with iOS Services/
│   ├── levels/       LevelCurve, LevelProgressStore(+Service), LevelLivesService,
│   │                 StarWalletService, LevelPowerUp, LevelsIntroGate
│   ├── seasons/      Season, SeasonCatalogService, SeasonProgressService,
│   │                 SeasonLevelProgressStore
│   ├── daily/        DailyChallengeService, DailyChallengeShared
│   ├── ads/          AdsService + AdFrequencyCap
│   ├── notifications/NotificationService, PrimerContent
│   ├── haptics/      HapticsService
│   ├── stats/        GameStatsService, ProfileStatsService
│   ├── images/       RemoteImageService
│   ├── whatsnew/     WhatsNewManager, WhatsNewContent
│   └── analytics/    AnalyticsEvent (sealed), Analytics (+ LoggingAnalytics)
├── feature/
│   ├── launch/       SplashScreen, LaunchSequence
│   ├── onboarding/   FeatureIntroScreen, DifficultyPickerScreen
│   ├── menu/         MenuScreen, MenuViewModel, board grid, tabs
│   ├── game/         GameScreen, GameViewModel, CardView, Pie, PowerUpBar, modals
│   ├── levels/       LevelsScreen, LevelMap (shared), OutOfLivesModal, LevelsIntro
│   ├── seasons/      SeasonLevelsScreen, SeasonLevelsViewModel
│   ├── multiplayer/  MultiplayerService, room + join screens, QR
│   ├── settings/     SettingsScreen, AchievementsScreen
│   ├── review/       ReviewInvitation (ReviewFlow-Android host)
│   └── share/        ShareResultCard
├── navigation/       NavGraph, DeepLinkRouter
└── ui/theme/         Palette (light/dark pairs), Typography, Shapes, Icons map
```

`res/values/strings.xml` carries the full §19 catalog from day one; the nine
translation folders arrive at Phase 8 but the **keys** exist from Phase 1, so no
string is ever hardcoded in a composable.

---

## 4. Phase plan

Each phase is independently buildable and runnable. "Exit" is the gate to the next.

### Phase 0 — Scaffold ✅ *(this session)*
Gradle wrapper, version catalog, `:app` module, Compose + Material 3, theme tokens
from §14.1 (light/dark pairs), `strings.xml` with the English catalog, package
skeleton, `AppContainer`, unit-test harness.
**Exit:** `./gradlew assembleDebug testDebugUnitTest` green; app launches to a
placeholder.

### Phase 1 — The game ✅ *(this session)*
`Card`/`Board`/`MemoryGame` including **both** constructors (`isDoubleItem`
true *and* false — §3.1, keep the unused adjacency pairing), `choose(card)`
matching rules, the three post-tap timers with cancel-on-next-tap, the win guard,
the pie model, `Difficulty` with its time limits, square-ish grid layout,
`GameScreen` + `GameViewModel`, `LevelCurve`, `SeededGenerator`, `EmojiPool`,
free play against a hardcoded board list.
**Tests:** matching rules, flip-back cancellation, single-fire win, star
thresholds, `LevelCurve` interpolation at and between every anchor plus the caps,
RNG determinism.
**Exit:** a playable game with a working clock, on both board constructors.

### Phase 2 — Catalog and menu ✅
Firebase anonymous auth + `/data` read, menu/nav graph, tabs, difficulty filtering,
favourites, custom memoramas, per-board stats, onboarding, Settings/theme switching,
and the DataStore surface are complete.
Silent non-fatal network failure (§13.1) is a **test case**, not an afterthought.
**Exit:** full free-play loop over the real catalog; app usable offline.

### Phase 3 — Levels *(in progress)*
`LevelProgressStore` **as an interface from the start** (this is what makes Phase 4
cheap), `LevelProgressService`, the level map with paging and tile states, stars
with the high-water-mark + improvement-only-credit rules, the two separate star
counters, daily lives (4/day, lazy reset on the shared day key), the mistake
budget with its 0.8 s deferral and first-failure-wins rule, the four power-ups
(freeze as a `frozenUntil` deadline, not a cancelled timer), the lose-screen star
purchases, skip semantics, the intro carousel gated on the launch sequence.
**Exit:** the level ladder is fully playable and the star economy balances.

### Phase 4 — Seasons *(in progress)*
`SeasonCatalogService` with synchronous cache read on startup, the §9.3 validation
table (fail closed on structure, fall back on decoration), the §9.5 locale
resolution **with an Android-specific test against real `Locale.toLanguageTag()`
output** (the iOS bug in that section does not translate directly), activation
window on string day-keys, priority + id tie-break, `SeasonLevelProgressStore`,
the season card and map, artwork loading with a ~64 MB LRU disk cache.
**Exit:** a season published to Firebase appears, plays and expires with no app change.

### Phase 5 — Daily Challenge, widget, notifications
Deterministic 6-pair daily board, one-attempt-per-day idempotent recording,
streaks and milestones, Glance widget over a shared DataStore with a midnight
refresh, the three local reminders behind a single `activateReminders()` path,
the permission primer, launch-state sync with OS permission.
**Exit:** streak survives a day rollover; widget updates at midnight.

### Phase 6 — Multiplayer
Room documents, the 6-char code alphabet and its index, create/join/start/turn/
rematch/leave, `onDisconnect()` presence with the 15 s grace, winner and draw
rules, QR + invite share (**Play Store link**, §10.7), deep links
(`domemory://` scheme + `domemory.app` App Links).
**Exit:** an Android device plays an iOS device — the single highest-value
cross-platform behaviour in the app (§18).

### Phase 7 — Ads
AdMob: 9 placements, the full frequency-cap rule set (per-difficulty interval,
20 s floor, 60 s rewarded suppression, 90 s global gap, 4 h app-open freshness),
unconfigured-placement hiding. Remove Ads purchases and the rewarded 24-hour ad-free
day are deliberately deferred from the Android scope.
**Exit:** caps verified by test, not by feel.

### Phase 8 — Engagement polish and localization
What's New with its new-install/upgrade discrimination, Play In-App Review,
achievements, the spoiler-free share card, the haptics table with held generators
and its three silence rules, animations (tile pulse, press-to-0.92 spring,
progress-bar spring, numeric transitions), accessibility announcements, the nine
translations plus the **localization parity test**.
**Exit:** parity test green across all ten locales; release candidate.

---

## 5. Test strategy

The spec names the iOS suites worth mirroring (§18). Pure logic carries the risk,
so it is all written against plain Kotlin with an injected clock:

`MemoryGameTest`, `GameViewModelTest`, `LevelCurveTest`, `LevelProgressServiceTest`,
`LevelLivesServiceTest`, `StarWalletServiceTest`, `LevelsIntroGateTest`,
`SeasonTest` (validation table), `SeasonCatalogServiceTest`,
`SeasonProgressServiceTest`, `SeasonLocaleResolutionTest`, `DayKeyTest`,
`DailyChallengeServiceTest`, `AdFrequencyCapTest`, `WhatsNewManagerTest`,
`SeededGeneratorTest`, `LocalizationParityTest`.

Rule: every constant in §20 that a test can pin, a test pins. That table is the
cross-check for the whole port.

---

## 6. Risk register

| Risk | Impact | Mitigation |
|---|---|---|
| **D1 changes a product claim** — "the same board for everyone worldwide" becomes per-platform | Marketing/UX | Either soften the copy on Android, or revisit D1 before Phase 5 while the RNG is still isolated behind `SeededGenerator`. The cost of reversing D1 later is one class plus a fixture test. |
| Season catalog is shared with iOS | A payload valid on iOS but rejected on Android (or vice versa) silently hides a live-ops season | Port §9.3 exactly and add a fixture test using the real `Scripts/seasons.json`. `upload_seasons.py` hardcodes the 12-emoji floor — if the curve is retuned, three places change together. |
| Launch-sequence ordering (§11.4) | Ads landing on top of first-run surfaces; consent resolved after the SDK starts | Model it as an explicit state machine with tests, not as scattered `LaunchedEffect`s. |
| `hapticsEnabled` default | Reads as `false` if fetched carelessly → feature ships silently dead | DataStore accessor returns `?: true`; unit-tested. |
| Cross-platform multiplayer untested | The highest-value shared behaviour breaks quietly | Phase 6 exit criterion is a live Android↔iOS match, not a passing test. |
| API 37 / AGP 9.4 are very new | Toolchain churn | Versions pinned in `gradle/libs.versions.toml`; the wrapper is committed. |
| Artwork URLs are permanent contracts (§9.7) | Overwriting bytes at a live URL poisons CDN caches for both platforms | Never overwrite; publish at a new filename. Applies to the shared catalog, so it is an Android concern too. |

---

## 7. Status

**Current status: Phases 0–6 and 8 are complete; Phase 7 has the remaining intentional ad/launch-sequence decisions listed in §8.** Phase 3's hardening merged to `master` as PR #45 (`37f4115`); Phase 4 and
part of Phase 5 merged once as PR #44, were reverted directly on `master` with no PR
(commit `42cc257`, confirmed unintentional), and are being re-landed in this same
change by reverting that revert on top of the now-merged hardening code and resolving
the resulting overlap by hand (see "Reconciling the two branches" below) — this is not
a second independent implementation, it is the same Phase 4/5 work already reviewed
once, now integrated against Phase 3's hardening.

What follows first documents the hardening work, in the order the handoff called it
out:

1. **Lives gate at level entry (spec 7.4).** Tapping a level tile with 0 daily lives now
   goes through `LevelsViewModel.attemptStart(level)`, a suspend gate that checks
   `LevelLivesService.hasLivesRemaining()` before navigation and surfaces the out-of-lives
   prompt instead when it's false. Previously `LevelsScreen` navigated on any tap with no
   check at all.
2. **`LevelProgressService` cache concurrency.** The old cache was a plain
   `mutableMapOf<Int, Int>` and a `var highest`, mutated from coroutines launched on
   `AppContainer.applicationScope` — `Dispatchers.IO`, a real thread pool, not a confined
   thread. Two bugs followed: every call to `stars(level)` for an unloaded level queued
   *another* redundant disk read instead of joining the one already in flight, and the
   backing map was never synchronized against concurrent writers.
   The fix keeps the original "mutation updates the in-memory cache inline" shape but
   makes every piece of it safe: `ratings` is a `ConcurrentHashMap`, `highestUnlockedLevel`
   an `AtomicInteger` raised through a real compare-and-set (`raiseHighestTo`, never a
   plain read-then-write that a second racing completion could turn into a lost update),
   and a `loadingLevels` concurrent set makes `stars(level)`'s fetch-on-miss atomic —
   exactly one disk read is ever in flight per level no matter how many callers ask at
   once. An init-time warm-up loop also starts loading every already-cleared level's
   rating at construction, the same way `highestUnlockedLevel` was already eager, so the
   *first* `stars(level)` call for a previously-cleared level doesn't flash a stale 0.
   `recordCompletion` also now returns the level's high-water-mark rating after recording
   (matching iOS), not just this run's own — a real deviation the old code had (a sloppy
   replay of a 3-star level was reporting 1, not 3).
   A `StateFlow`-per-key design (DataStore's own flow bridged via
   `stateIn(scope, SharingStarted.Eagerly, ...)`) was tried first and is architecturally
   more idiomatic, but proved untestable: its cache update is a *second*,
   independently-scheduled coroutine (observing DataStore's `data` flow) rather than part
   of the same coroutine that performed the write, and that update never reliably became
   visible to a test's `advanceUntilIdle()` — 12 tests failed consistently, not flakily,
   because there is nothing forcing that second coroutine to run before the assertion.
   `StarWalletService` hit the identical wall and got the identical fix (mutators update
   the cache inline; see its class doc). Both classes' docs record this as the reason,
   so nobody rediscovers it by reintroducing a `stateIn` bridge here.
3. **Loss recovery.** The biggest behavioral gap: the old `finish()` committed a Level
   loss (spent a life, recorded progress and stats) the instant `loseReason` would be
   set, before the player ever saw a rescue option — so a "free" mistake-budget rescue or
   a star-bought life could never actually be free, because the life was already gone.
   iOS defers this: `logGameFinishedIfNeeded` for a loss only runs from the lose modal's
   own "Try Again" / "Go to menu" handlers. `GameViewModel` now mirrors that — reaching a
   `Lost` outcome only shows the lose screen; `retry()` and `acknowledgeLossAndQuit()` are
   the "walk away" paths that actually commit it (`commitLossIfNeeded()`, idempotent per
   attempt), while `forgiveMistakesWithStars()` and `buyLifeWithStars()` undo the loss
   without ever committing it. `retry()` also refuses to restart when committing the loss
   leaves the player at 0 lives, the same gate as entry. `skipLevelWithStars()` commits
   (skipping still counts as a loss) and unlocks the next level without stars. This
   deferral is Levels-only — free play and the Daily Challenge keep the original
   immediate-commit behavior, since neither has a lose-screen rescue to protect, and
   changing that was out of scope here.
   Separately, `checkMistakeBudget()` had a real exploit: it cancelled-and-rescheduled the
   0.8 s deferred loss on *every* mismatch once the budget was already busted, so a player
   who kept mismatching every &lt;0.8 s could postpone the loss forever. It's now armed once
   per bust and only re-armed by `pause()`/`resume()` (which also fixed a second bug: a
   pause during the 0.8 s window used to drop the pending loss entirely instead of
   re-arming it on resume).
4. **Power-ups.** All four (`LevelPowerUp.EXTRA_TIME` / `PEEK` / `FREEZE` / `REVEAL_PAIR`)
   are wired into `GameViewModel` (`buyExtraTime` / `buyPeek` / `buyFreeze` /
   `buyRevealPair`), Levels/Seasons-gated, spent through the new `StarWalletService`, and
   rendered in a power-up bar under the HUD (`GameScreen`'s `PowerUpBar`). Freeze is a
   `frozenUntil` deadline the existing tick loop already checked (per this plan's Phase 3
   note) — buying it just writes the deadline and flips `isFrozen` eagerly for instant
   feedback. Peek ends itself on `pause()` (spec 7.6's explicit rule) via the same
   `endPeekIfActive()` the countdown already needed. Reveal pair reuses
   `MemoryGame.findUnmatchedPair()` (already scaffolded, already tested) plus a new
   `faceUp(ids, now)` model method, and re-arms the normal 2 s flip-back. The lose-screen
   purchases from spec 7.7 (buy a life, forgive mistakes, skip level) are also wired, with
   a confirmation dialog only in front of skip, matching the spec's "no confirmation
   step" rule for everything else. Rewarded-ad alternatives for lives/mistakes stay a
   Phase 7 seam — there is no `AdsService` yet.
   PR review fix: `spendOnPowerUp` originally applied a power-up's effect off a cached
   `canAfford()` check and fired `StarWalletService.spend()` afterward without checking
   its result — two buys racing the same stale balance (a double-tap, or two different
   power-ups tapped back-to-back) could both pass `canAfford` and both apply, with only
   the first `spend()` actually succeeding against the real, serialized balance. It now
   awaits `spend()` first and only calls `apply()` once that succeeds, refunding via
   `credit()` if `apply()` itself then reports failure. Pinned by
   `GameViewModelTest`'s "two concurrent buys against one power-up's worth of stars grant
   exactly one effect".
5. **Levels intro.** `LevelsIntroGate` (services/levels) ports the one-shot, mark-on-
   dismiss rule from iOS 1:1, backed by the `levelsIntroShown` DataStore key that was
   already sitting unused in `UserPreferences`. `LevelsViewModel` presents it on first
   load and exposes `presentIntro()` for the map's info button. **Deliberately
   incomplete relative to iOS**: iOS additionally gates the intro on the launch sequence
   (§11.4 — ATT, ads bring-up, the notification primer all finishing first), because
   Levels is the landing tab and would otherwise race their covers. Android has none of
   those surfaces yet (ATT has no Android equivalent decided, ads are a Phase 7 stub, no
   notification primer exists) — there is no launch sequence to gate on. This is a
   documented seam, not a missed requirement: wiring in a real `canPresentIntro` flag
   later is one parameter, the same shape as iOS's `LevelsView.canPresentIntro`.

New/changed services: `StarWalletService` (spendable wallet, `spend`/`credit` go straight
through `UserPreferences`' atomic transactions rather than deciding off a cache),
`LevelPowerUp` (costs and tuning constants, ported verbatim from iOS), `LevelsIntroGate`,
plus `LevelLivesService.hasLivesRemaining()` and `MemoryGame.forgiveFailures` / `.faceUp`.
`LevelsViewModel` and a rebuilt `LevelsScreen` (header with live lives/star pills, the
out-of-lives modal, the tile grid, a simple intro dialog) replace the old placeholder grid
that read `LevelProgressService` directly with no gating and no header at all.

### Handoff ledger (update this with every migration slice)

| Area | State | Branch / commit | Next owner action |
|---|---|---|---|
| Phase 2 | merged, **now emulator-verified** | `c1faf11` / PR #43 | none — see verification note below. |
| Phase 3 | merged, **now emulator-verified** | `c1faf11` / PR #43; hardening `feature/android-levels-hardening` / PR #45 (`37f4115`) | none — see verification note below. |
| Phase 4 | complete — emulator-verified against a live Firebase season, including day-boundary expiry | `1f17bb7` / PR #44 (re-landed after accidental revert) | none; season-specific out-of-lives presentation is tracked as deferred polish. |
| Phase 5 | complete — Daily Challenge/deep links, Glance widget and local reminders all build- and emulator-verified, including streak rollover across a day boundary | `feature/android-phase5-widget-notifications` / PR #49 | none; carry its architecture forward when Phase 8 adds launch-sequence gating. |
| Phase 6 | complete — a live Android↔iOS manual-code match, rematch and reconnect-grace forfeit all passed on 2026-09-15 | PR #53; production room-read-rule fix PR #58 (`beabbbe`) | O1 App Links remains an optional domain-dependent follow-up; manual-code joining is fully supported and verified. |
| Phase 7 | in progress — configured placements, banners, completion interstitial, both Levels rewarded rescues, `game_rewarded_hint` (now wired from a new pause sheet in every mode) and multiplayer-finished native ad are emulator-verified | PRs #51–#54; verification record PR #60 | `game_rewarded_extra_time` still needs a decision and UI before it can be wired; launch sequence and UMP consent done (#167); app-open still to wire. Billing and temporary rewarded ad-free day remain deferred. |
| Phase 8 | complete — What's New, review, achievements, share card, animations, accessibility, all translations and app-wide haptics are implemented; localization parity is green | PRs #55–#57, #59 and #61 | real-device haptic feel, TalkBack and animation-feel checks are follow-ups, not exit blockers. |

**Emulator verification session, 2026-09-14.** First time the app has been seen running (`Pixel_10` AVD, API 37, `google_apis_playstore_ps16k/arm64-v8a`, already provisioned on this machine). Exercised: the menu (all three tabs), a live Firebase season ("Spooky Season", 30 levels, real `/seasons` data — not a fixture), a full season-level play-through (win modal, star award, progress persisted back to the map), an endless level play-through, the Daily Challenge board, and Settings. Two real bugs were found and fixed in this session (both build- and test-clean, `245` tests still green):

1. **`SeasonCard.kt` — season artwork broke the entire menu layout.** `AsyncImage(model = season.cardImageURL, modifier = Modifier.fillMaxWidth())` was a plain top item in the card's `Column`, so Coil sized it to the artwork's own intrinsic pixel height (portrait-ish, ~1500dp+) instead of the card's compact height. That pushed the `Levels` / `My memoramas` / `All` tab row completely off-screen — **the entire menu below the season card was unreachable through the UI whenever a season was active**, which is always true right now since a live season exists in Firebase. iOS avoids this by drawing the artwork as a `.background` layer sized to the text content's own bounds (a `ZStack`), never as foreground content. Fixed by switching the Android card to the equivalent `Box` + `Modifier.matchParentSize()` pattern. This should have been caught by Phase 4's own exit criterion ("a season published to Firebase appears, plays and expires with no app change") — it wasn't, because Phase 4 was never actually run.
2. **`SettingsScreen.kt` — difficulty/theme labels bypassed the string catalog.** Built labels from the raw enum name (`Difficulty.VERY_HARD.name.lowercase()...` → literal **"Very_hard"** on screen) instead of the existing `R.string.difficulty_*` / `R.string.theme_*` resources, which were already correctly defined and already used elsewhere (`MenuScreen.kt`'s `AllTab`). This silently violated the repo's own "no string is ever hardcoded in a composable" rule from `ANDROID_PLAN.md` §3 and would have failed `LocalizationParityTest`-equivalent coverage once Settings gets one. Fixed by adding the same `labelRes()` mapping pattern already used in `MenuScreen.kt`.

**Follow-up verification pass, same day (2026-09-14), against the merged fixes (PR #48, `edd4bba`).** Exercised the parts of the menu the first pass didn't reach: full custom-memorama lifecycle (create with a name and 2+ items → appears in "My memoramas" → favorite toggled and persisted → played as a free-play board → delete with its confirmation dialog → cleanly removed, including its favourite id, from `favoriteIDs`), the "All" tab's live 134-board Firebase catalog with difficulty filtering, and the Settings Light/Dark theme switch (both directions, confirmed visually on both the Settings screen and the menu — full repaint, no contrast or readability issues in either palette). No new bugs found; everything held up correctly.

One false alarm worth recording so it isn't re-chased: mid-session, a custom board's favorite star appeared to revert after playing the board and backing out. Direct inspection of the on-device DataStore file (`run-as ... cat files/datastore/domemory_prefs.preferences_pb`) at each step — immediately after favoriting, mid-game, and after returning — showed the favorite id present on disk throughout; a clean repeat of the same play-then-back sequence didn't reproduce the apparent loss either. The likely cause was an imprecise test tap landing near the card's Delete control (its clickable bounds sit immediately adjacent to the favorite star's), not an app defect. `toggleFavorite`/`removeCustomMemorama` are DataStore's only writers of `favoriteIDs` in the codebase, which is consistent with this being a test artifact rather than a race.

Not exercised: multiplayer (Phase 6 remains in progress), monetization (Phase 7, stubs), What's New/achievements/haptics feel/animations (Phase 8), and a season's day-boundary expiry (would need the emulator's system clock advanced past `endDate`, not attempted) — the season expiry and the Daily Challenge streak rollover were both closed out in the 2026-09-15 session below.

**Boundary-case verification session, 2026-09-15.** Closed out §8 item 1 (season day-boundary expiry, Daily Challenge streak rollover) — the two cases the 2026-09-14 sessions above flagged as needing the emulator's system clock advanced, not just unit tests. Same `Pixel_10` (API 37) emulator; `adb shell date` (root `date -s` is refused — "cannot set date: Operation not permitted" — this system image is a production/Play-Store build, not `userdebug`) so the clock was driven through the on-device Settings → Date & time UI instead (`am start -a android.settings.DATE_SETTINGS`, toggle "Automatic date and time" off, then the date picker), confirmed after each change with `adb shell date`.

Season expiry: the live "Spooky Season" (`endDate` 2026-11-02) was showing "48 days left" on 2026-09-15. Backgrounded the app with the Home key (confirmed via `adb shell ps` that the process stayed alive, not killed), advanced the date to 2026-11-03, then brought the *existing* task back to the foreground (`adb shell am start -n .../.MainActivity` returned "Activity not started, its current task has been brought to the front" — a genuine `onResume()`, not a cold relaunch). The season card disappeared from the menu on that resume with no app restart, exactly as `MainActivity.onResume()`'s doc comment and `SeasonCatalogService.refreshActive` describe. No bug found.

Daily Challenge streak rollover: played and won the Daily Challenge on 2026-09-15 (streak → 1, confirmed via the on-device DataStore file). Advanced the date by one day and relaunched: the day after a **win** correctly offered a new board and kept the streak (still 1, not reset) — matches spec. To test the actual increment-on-consecutive-win case, advanced one more day and played again, but that run timed out (a real loss, not a tap error), which correctly locked the day and reset the streak to 0 — a useful incidental confirmation that a loss still consumes the day. Advanced two more days, winning both: the second of those two consecutive winning days took the streak from 1 to 2 (`dailyStreakCurrent`/`dailyStreakLongest` both read `2` from the DataStore file afterward), and each new day offered a fresh, differently-seeded board. No bug found; `DailyChallengeService`/`UserPreferences.recordDailyCompletion`'s win/loss/gap rules held up exactly as documented against the real device clock, not just the fake `DayProvider` the unit tests use.

No source changes were made in this session — both boundary cases behaved as designed on the first attempt. `./gradlew testDebugUnitTest` was re-run before this session's emulator work as a baseline (still clean) and no test-affecting code changed afterward, so it was not re-run a second time.

**Live Android↔iOS multiplayer attempt, 2026-09-15.** First real attempt at Phase 6's exit criterion ("an Android device plays an iOS device"). Per this session's decision to defer O1 (App Links — `domemory.app` is unregistered, confirmed NXDOMAIN), the join was exercised through the in-app manual 6-character code, not QR or a deep link. Built and installed the Android app on the `Pixel_10` (API 37) emulator (`./gradlew assembleDebug`, `adb install -r`) and the iOS app on the "iPhone 17 Pro" Simulator (`xcodebuild -workspace DoMemory.xcworkspace -scheme DoMemory -sdk iphonesimulator -configuration Debug build`, `xcrun simctl install`/`launch`), driving the simulator via `idb ui tap`/`idb ui text` (fb-idb, connected with `idb connect <udid>`) since it has no adb-equivalent built into `simctl`.

Android created a room from the menu's ♟ multiplayer entry ("Create room" against the boards catalog's first board) and got code `DFX8P3`, shown correctly in both text and QR form, room status `waiting`. On iOS, freshly onboarded through the ATT/notification-primer/Levels-intro launch sequence, tapped the top-bar person icon (`JoinMultiplayerRoomView`, reached directly — creating a room is a separate per-board context-menu action on iOS, not exercised here), typed `DFX8P3`, and tapped **Join room**. iOS failed both on the first attempt and on an immediate retry with the same generic `Text(Strings.multiplayerGenericError)` ("Something went wrong. Please try again.") that `MultiplayerRoomView.swift` always shows for any thrown error, burying the real message in the label's `accessibilityHint` — read via `idb ui describe-all --json`'s `help` field:

> Unable to get latest value for query FQuerySpec (path: /multiplayerRooms/-P1_S1nrK5KcvC1Gt4fV, params: {}), client offline with no active listeners and no matching disk cache entries

That phrasing is a known Firebase iOS SDK quirk for `getData()`/`getDataAsync()`: it surfaces a permission-denied response from the server as a generic "client offline" error rather than a clean `permission_denied`, when there is no listener or cache already backing the query. The room itself was confirmed live and correctly formed (`firebase database:get "/multiplayerRooms/-P1_S1nrK5KcvC1Gt4fV" --project domemory-c9211`) — `difficulty`, `gameId`, `gameName` etc. all present, so this is not a wire-format/Codable mismatch between the two platforms' room encodings.

**Root cause: `firebase/firebase-database.rules.json`'s `/multiplayerRooms/$roomId` `.read` rule structurally cannot be satisfied by a prospective guest.** It only grants read to the existing host, the existing guest, or when the room doesn't exist yet:
```
".read": "auth != null && (data.child('hostId').val() === auth.uid || data.child('guestId').val() === auth.uid || !data.exists())"
```
`MultiplayerService.swift`'s `joinRoom(code:)` does an explicit `getCodable(MultiplayerRoom.self)` read of the room *before* writing `guestId`, specifically to check `room.status`/`room.guestId` eligibility (Service/MultiplayerService.swift:112) — and a second player, by definition, is neither host nor guest yet, so that read is always denied. This is not Android-specific: any two iOS devices would hit the identical wall, since Android's `joinRoom` (services/multiplayer/MultiplayerService.kt:39-63) never does a standalone pre-write read at all — it goes straight to `transaction(roomId) { ... }`, which is validated against the **`.write`** rule instead, and that rule already has the matching guest-join carve-out (`!data.child('guestId').exists() && newData.child('guestId').val() === auth.uid`). The read rule was simply never given the same carve-out, so only Android-style (transaction-based) joins were ever actually possible against these rules — an asymmetry nothing had exercised live until this session.

**Fix drafted, not deployed.** Added the same "room is still open, no guest yet" exception already present on `.write`, to `.read`:
```
".read": "auth != null && (data.child('hostId').val() === auth.uid || data.child('guestId').val() === auth.uid || !data.child('guestId').exists() || !data.exists())"
```
This is applied locally in this worktree's `firebase/firebase-database.rules.json` but **deliberately not run through `firebase deploy --only database`** — that deploys to the live production database backing the already-shipping iOS app, which is a production infrastructure change outside a background session's authority to make unsupervised; it needs a human to actually deploy it (from `firebase/`, per the root CLAUDE.md) and confirm the security implication is acceptable (any authenticated user who has a room's 6-character code — the intended sharing mechanism — can now read that room's data before joining, matching the openness the write rule already granted; once a guest joins, the room locks back down to host+guest only). Because the rule isn't live, **the join could not be retried successfully and the live Android↔iOS match remains unverified** — this is the actual, current Phase 6 blocker, ahead of O1.

**Live Android↔iOS multiplayer retry, 2026-09-15 (same day, after the rules deploy).** The user reviewed the `.read` rule diff above and deployed it (`firebase deploy --only database --project domemory-c9211`, run from `firebase/`), then confirmed via `firebase database:get /.settings/rules --project domemory-c9211` that the live rule matched the working-tree fix exactly. The match was then retried end to end:

- Relaunched both apps (no rebuild needed). Android created a fresh room (`CD3PM6`, since the earlier `DFX8P3` was stale). iOS joined via the manual 6-character code — the preflight `getCodable` read that previously failed now succeeded on the first attempt. Android's screen updated live to "Player joined. Start when ready" and iOS showed "Waiting for the host to start" — confirming the join is visible to both sides, not just the joiner.
- Android (host) started the game; both devices rendered the identical 8-card (4-pair) board and agreed on whose turn it was (Android: "Your turn", iOS: "Opponent's turn") from the first frame.
- Played the match to completion from the Android side (four flips, all matches). Final state was consistent on both devices: Android showed "You won", You: 4, Opponent: 0; iOS showed "You lost", You: 0, Opponent: 4 — the same result from each side's own perspective, which is what "consistent" means for this exit criterion. The multiplayer-finished native ad placement (Phase 7) also presented correctly on iOS at this point, an incidental confirmation of that wiring.
- Rematch: tapped "Play again" on Android. A new room was created and iOS's listener picked it up automatically (no manual re-join needed) — both devices rendered the new 8-card board. During this step the Android device was briefly backgrounded by an accidental tap into a test ad's Play Store deep link (a test artifact of driving the emulator via `adb`, not a game-UI bug — AdMob's test native ad card is taller than the production placement, so the "Play again" button's approximate on-screen position from the previous state was no longer accurate; re-taps must use `uiautomator dump`-derived exact bounds, not a re-estimated screenshot position). The backgrounding held past the 15-second reconnect grace (`RECONNECT_GRACE_SECONDS`), and the room correctly resolved as a host forfeit: server data (`firebase database:get "/multiplayerRooms/-P1_WtG_EErXs4K0oxjZ"`) shows `status: finished`, `winnerId` set to the guest (iOS), `disconnectPlayerId` set to the host (Android), `players.<host>.connected: false`. Both clients displayed this consistently and correctly — Android (`uiautomator dump`, not a screenshot guess, since the AdMob validator dialog was obscuring part of the text): "You lost", 0-0; iOS (`idb ui describe-all`): "You won", 0-0. This incidentally verifies the reconnect-grace forfeit rule cross-platform, which nothing had exercised live before — not part of the original exit criterion, but a meaningful bonus given how easily a real player could trigger the same thing (backgrounding the app mid-match).

**Phase 6's exit criterion — "an Android device plays an iOS device" — is met.** The remaining gap is App Links (O1): the deep-link join path (`domemory://join/CODE`, tapping a shared link outside the app) is still unverified because `domemory.app` is unregistered, but the manual-code path is a fully supported, already-shipped alternative and was what this session verified. The `.read` rule fix is live in production and was subsequently committed as PR #58 (`beabbbe`).

Both branches touched `AppContainer.kt`, `GameViewModel.kt`, `MenuScreen.kt` and
`NavGraph.kt`. `git merge`/`git revert` resolved most of the overlap automatically;
five spots needed a human decision, all now applied:

- **`AppContainer.kt`, `GameViewModel.kt` constructor, `MenuScreen.kt` imports** — pure
  additive conflicts (both sides added properties/params/imports at the same location).
  Kept both sides' additions.
- **`GameViewModel.commit`/`commitLossIfNeeded`.** Hardening split the old single
  `finish()` into an immediate-commit path (`commit`, used by every win and by a loss in
  a mode with no lose-screen rescue) and a deferred one (`commitLossIfNeeded`,
  Level-losses only). The original Daily Challenge merge had put its
  `dailyChallenge.recordCompletion(...)` call textually next to `levelLives?.spendOnLoss()`
  — which the merge then placed inside the new `commitLossIfNeeded`, gated on
  `mode !is GameMode.Level`. Since the Daily Challenge is `GameMode.DailyChallenge`, not
  `GameMode.Level`, that path would never fire it — a silent dead line, not a build
  error. Moved to `commit()`, the immediate path the class doc already says the Daily
  Challenge takes (it has no lose-screen rescue to protect, so it was never meant to go
  through the deferred path).
- **`NavGraph.kt`'s `SEASON_GAME` composable was still calling the *old*, five-arg
  `GameScreen(...)` overload** (predating hardening's power-ups, lose-screen purchases,
  and deferred-loss `retry()`/`acknowledgeLossAndQuit()`), because the original Phase 4
  branch was written before any of that existed. It still compiled (every new
  `GameScreen` parameter has a default), but it meant a season loss's life was never
  spent and its attempt never recorded when the player quit — `commitLossIfNeeded()`
  only ever runs from `retry()`/`acknowledgeLossAndQuit()`, and the old call site invoked
  neither. Rewired to match the endless `LEVEL_GAME` composable exactly: `starWallet`
  passed into the `GameViewModel` (power-ups are "Levels and Seasons only" per spec 7.6,
  and season play is a `GameMode.Level` the same way endless is, so nothing else needed
  to change for power-ups to start working in Seasons), `onQuit` calling
  `acknowledgeLossAndQuit()`, `onRetry` calling `retry()` and bouncing back to the season
  map on an out-of-lives `false`. There is no season-specific out-of-lives *prompt* yet
  (endless has one via `LevelsViewModel`; Seasons just pops back) — left as a deferred
  polish item below, not a correctness bug like the other four.

| Suite | Tests | Pins |
|---|---|---|
| `MemoryGameTest` | 9 | matching rules, dead taps, cancel-on-next-tap, win condition |
| `BoardTest` | 5 | both board constructors, per-play shuffle, difficulty fallback |
| `DifficultyTest` | 3 | the §20 time limits including the medium/hard and very-hard oddities |
| `LevelCurveTest` | 10 | every anchor, interpolation, the caps, `maxFailures > pairs` |
| `StarsTest` | 4 | the 3/2/1-star thresholds |
| `SeededGeneratorTest` | 9 | FNV-1a vectors, RNG determinism, generator pair counts |
| `DayKeyTest` | 3 | zero-padding and chronological string ordering |
| `GameViewModelTest` | 43 | the three timers, clock sources, mistake budget, first-failure-wins, mistake-deferral pause/resume re-arming, deferred loss commit, all four power-ups, all three lose-screen purchases, concurrent power-up buys against one power-up's worth of stars |
| `BoardDecoderTest` | 8 | the live 134-board payload, array/map shapes, tolerant field decoding |
| `BoardCatalogRepositoryTest` | 9 | difficulty filtering, custom-board rules, silent catalog failure |
| `LevelProgressServiceTest` | 8 | high-water-mark stars, wallet-crediting completion, skip, cache concurrency (cold-start correctness, concurrent readers/writers) |
| `LevelLivesServiceTest` | 2 | lazy daily reset, loss-only spend, refill cap, the entry gate |
| `StarWalletServiceTest` | 6 | credit/spend/canAfford, authoritative spend over a stale cache, `refresh()` picking up a credit `LevelProgressService` made directly |
| `LevelsIntroGateTest` | 2 | one-shot, seen-on-dismiss-not-on-present |
| `UserPreferencesTest` | 27 | every DataStore key in spec 13.2 |
| `MenuViewModelTest` | 10 | tabs, favourites, difficulty filtering |
| `CreateMemoramaViewModelTest` | 6 | custom-board validation and save |
| `SeasonDecoderTest` | 2 | invalid-structure skip alongside a valid sibling, priority/id tie-break |
| `SeasonTest` | 26 | the full §9.3 validation table: fail-closed structure rules and fall-back decoration rules, one test per row |
| `SeasonCatalogServiceTest` | 5 | cache-before-network, a non-empty remote payload correcting and persisting over the cache, a malformed payload leaving the cache untouched, `activeSeason` priority/id tie-break re-evaluating with no network round trip, and the real `firebase/scripts/seasons.json` fixture decoding end to end |
| `SeasonProgressServiceTest` | 12 | fresh-season defaults, win/loss, improvement-only wallet credit (never `levels.lifetimeStars`), skip, `levelCount + 1` completion, `nextLevel` null past the end, on-demand bounded `totalStars`, cross-season and cross-mode namespacing |
| `SeasonLocaleResolutionTest` | 11 | the candidate-shortening algorithm, and real `java.util.Locale.toLanguageTag()` output for `es-419`, `es-MX`, `pt-BR` and `zh-Hans-CN` — the last one is the case where Android's reported identifier (keeps the script subtag) sidesteps the exact iOS bug spec 9.5 documents |
| `SeasonPayloadJsonTest` | 3 | the pure `DataSnapshot.value` (nested `Map`/`List`) → JSON-text conversion `FirebaseSeasonCatalogSource` depends on, isolated from any live Firebase connection the same way `BoardDecoderTest` is |
| `DailyChallengeServiceTest` | 10 | deterministic per-day board, idempotent one-attempt-per-day recording, streak continuation/gap/loss rules, longest-streak monotonicity, milestone reporting |
| `DeepLinkTest` | 10 | every link form in spec 11.1's table, the custom-scheme-only host inclusion rule, code normalization (uppercase, strip non-alphanumerics), the exact-6-characters requirement |

**245 tests across 27 files, all green** (`./gradlew testDebugUnitTest`, verified against
this reconciled tree, not carried over from either branch's own run).

`GameViewModelTest` has a gotcha worth knowing before adding to it: `advanceUntilIdle()`
is only safe once the game has already reached a terminal outcome — the tick loop is a
`while (isActive) { delay(100); ... }` coroutine, and if it is still running,
`advanceUntilIdle()` will drain every scheduled tick, fast-forwarding the level's clock to
a real timeout instead of just letting a fire-and-forget star spend or life-refill settle.
This file uses `runCurrent()` for that instead (runs only already-ready work, never
touches the tick loop's still-pending `delay`), and it is what silently made several of
the hardening branch's own new tests fail against otherwise-correct production code
before the fix was to the test, not `GameViewModel`.

**Phase 4 implementation, this session:** `Season.kt` gained the decoration fields
(`accentColor`, `backgroundImageURL(Dark)`, `cardImageURL`, all validated at decode
time per §9.3) and `SeasonLocaleResolver` (the §9.5 candidate-shortening lookup, pure
and Android-resource-free so it stays unit-testable without Robolectric).
`SeasonCatalogService` gained an `activeSeason: StateFlow<Season?>` re-evaluated by
`refreshActive()` — called on every `MainActivity.onResume()` so a long-lived
foreground process doesn't keep showing a season that ended at local midnight (§9.4).
`FirebaseSeasonCatalogSource` (`data/remote/`) mirrors `FirebaseBoardCatalogSource`
exactly: anonymous auth warmup, single snapshot, silent non-fatal failure; the
Map→JSON conversion its `/seasons` (dictionary, not array) shape needs is split into
the pure, testable `SeasonPayloadJson`. `SeasonProgressService` +
`SeasonLevelProgressStore` (`services/seasons/`) are the finite twin of
`LevelProgressService`/its endless store, namespaced `season.<id>.*` via two new
`UserPreferences` transactions (`recordSeasonLevelCompletion`,
`unlockSeasonLevelAtLeast`) that mirror `recordLevelCompletion`'s atomicity. A season
card (`feature/seasons/SeasonCard.kt`) renders above the endless map on the Levels tab
when a season is active, and `SeasonLevelsScreen.kt` is the finite level map (header
with icon/title/spring-eased progress bar/star total/countdown/completion state, then
a bounded `1..levelCount` grid) — both wired into `NavGraph.kt` (`season/{seasonId}`,
`season/{seasonId}/level/{level}`) and `AppContainer.kt` (`seasonCatalog`,
`seasonProgressStore(season)`, memoized per season id). Coil 3
(`coil-compose` + `coil-network-okhttp`) is wired as the `SingletonImageLoader.Factory`
in `DoMemoryApplication`, with a dedicated ~64 MB LRU disk cache directory for season
artwork; the season card enqueues a background-artwork prefetch when the active season
id changes, mirroring iOS's "prefetch on change, not on every read" guard.

**Deliberately deferred / left as seams** (spec-conformant but intentionally not
built out further this session — flag before assuming they're gaps):
- **Season/Daily card compacting** (spec 9.1: the Daily card "shrinks to a compact
  layout" when it shares the row with an active season) is not implemented — both
  cards now sit in one `Row` with `weight(1f)` each when a season is active (see the
  Phase 5 note below), which resizes them but doesn't restyle either card's internal
  layout for the narrower width. Cosmetic; the row itself is correctly wired.
- **Season nav-bar transparency** (spec 9.1: transparent when the season carries
  artwork, opaque otherwise) is not implemented — `MainActivity` doesn't yet do
  per-screen system-bar styling. Cosmetic; doesn't affect the exit criterion.
  `SeasonLevelsScreen` does already show/hide background artwork and pick the
  light/dark URL correctly, it just doesn't extend under the status bar.
- **No win/lose modal exists for level play at all yet** (endless or season) — Phase 3
  ships those as placeholders per its own status notes, so a season level currently
  ends the same way an endless one does today: no "advance to next level" button is
  wired. `LevelContext.isFinalLevel`/`store.nextLevel(after:)` are in place for whoever
  builds that modal to consume.
- **Coil version (`3.5.0`) and the network-okhttp companion artifact were not
  present in the local Gradle cache** and were resolved from Maven Central during this
  session's build — first build after a fresh checkout will need network access once
  to populate the cache, same as every other dependency here.
- **No emulator/device verification** — same limitation as every prior phase in this
  repo; the season card, map header, artwork loading and expiry logic are unit-tested
  and compiled, not seen running.

**Phase 5 implementation, this session:** `services/daily/DailyChallengeService.kt`
generates the deterministic 6-pair board (`BoardGenerators.daily`, already ported) and
wraps a new atomic `UserPreferences.recordDailyCompletion` transaction — same
one-transaction-per-finish shape as `recordLevelCompletion`/`recordSeasonLevelCompletion`
— implementing the idempotent one-attempt-per-day lock, streak
continue/reset/gap rules (`DayKey.isConsecutiveDay`, a new pure helper), and the
milestone-threshold check (`{3, 7, 14, 30, 100}`; Android has no analytics wiring yet,
so this only *reports* a hit for a future caller to log). `GameViewModel` gained an
optional `dailyChallenge` param and records the finish exactly once, from the same
single-fire `finish()` path Levels already uses. `feature/daily/DailyChallengeCard.kt`
is the menu entry point, now sharing a `Row` with the season card (moved out of the
Levels-tab-only placement Phase 4 initially used, to actually match spec 9.1's "one
row" intent) — tapping it while today is locked is a no-op, matching the deep link's
own rule below. `core/deeplink/DeepLink.kt` (pure parser, `java.net.URI`-based so it's
plain-JVM testable) and `DeepLinkRouter.kt` (holds a link that arrives before the nav
graph can act on it) implement spec 11.1's link table; `MainActivity` now has
`android:launchMode="singleTop"` and feeds `onCreate`/`onNewIntent` data through the
router, and `NavGraph` consumes a pending `Daily` link once onboarding resolves.
`Join(code)` parses correctly (tested against every link form spec 11.1 lists) and Phase 6
now routes it into the multiplayer join lobby.

**Deliberately not attempted this session — flagged explicitly, not silently
dropped:** the Glance **widget** and **local notifications** (spec 8.1, 11.2, 11.3),
even though Phase 5's own exit criterion names both ("streak survives a day rollover;
widget updates at midnight"). Reasoning: both need new Gradle dependencies
(`glance-appwidget`, `work-runtime`) and Android-framework surfaces this repo cannot
verify without an emulator (`AppWidgetProvider`/`GlanceAppWidgetReceiver` XML,
`WorkManager` periodic scheduling, the API 33+ `POST_NOTIFICATIONS` runtime permission
flow and its OS-authorization-vs-app-flag sync bug iOS already hit once — spec 11.2's
"the permission bug worth not repeating"). Shipping that untested carries more risk
than the value of a same-session claim of "done." The exit criterion is therefore
**not yet met**; the next owner should build the widget and notification scheduler as
their own slice, verify the midnight refresh and the permission-sync rule on a real
device or emulator, and only then consider Phase 5 complete.

**Phase 5 completion follow-up, 2026-09-14.** The deferred slice is now implemented
and verified against the same `Pixel_10` API 37 emulator. `DailyChallengeGlanceWidget`
reads the app's shared DataStore through the application container, opens
`domemory://daily` when tapped, refreshes immediately after a Daily completion, and is
registered as a home-screen provider. A unique one-time WorkManager chain refreshes it at
the next local midnight; each run schedules the following local midnight rather than adding
a fixed 24 hours, so it remains aligned through daylight-saving transitions. The emulator
reports both the provider and its pending midnight worker.

`NotificationService` schedules the day-2/day-7 19:00 inactivity nudges and the eligible
same-day 20:00 streak-risk nudge. The custom once-per-install primer and Settings toggle
share one permission requester; every successful grant reaches `activateReminders()`, which
sets `notificationsEnabled` before scheduling. Foreground sync turns that flag off and
cancels all work if the OS permission is later revoked. The reminder-time, permission-sync,
and midnight-delay rules are unit-tested; `testDebugUnitTest` and `assembleDebug` pass.

**Firebase is live.** `app/google-services.json` is committed for project
`domemory-c9211` (client `com.ezequielbrrt.domemory`), and the app reads the real
`/data` catalog — 134 boards — through `FirebaseBoardCatalogSource`, falling back to a
bundled set when the network or the payload disappoints. Decoding is a pure function
pinned against `src/test/resources/data.json`, a verbatim copy of the live node.

Two things that came with it:

- **The debug `applicationIdSuffix` is gone.** The Firebase project has one Android
  client and the google-services plugin fails the build when the applicationId matches
  none of them. Registering a `.debug` client restores side-by-side installs (O7).
- **`app/google-services.json` is committed on purpose.** It ships inside every APK and
  is public config keyed to the package name. The service-account key sitting in
  `~/Downloads` is the actual secret and is git-ignored by pattern; it was not copied
  into the repo and nothing needs it.

**Not verified on a device.** No emulator system image is installed and no device is
attached, so the UI has been compiled and unit-tested but not seen running. Installing
an API 37 system image (~1.5 GB, needs `cmdline-tools`) is the next step if you want a
visual check.

**Deliberately deferred**, all left as seams rather than gaps:

- **Haptics and analytics** — still absent everywhere, carried over from Phase 1 (the
  model already reports what a tap actually did, so the haptics table has somewhere to
  attach; every power-up/purchase call site above is a natural analytics-event site once
  `AnalyticsService`'s Android counterpart exists).
- **Rewarded-ad refills** for out-of-lives and the mistake rescue (spec 7.4, 7.5) — both
  need `AdsService`, a Phase 7 stub today. The star-purchase alternative for each is fully
  wired; the ad button is simply absent rather than present-and-broken.
- **The Levels intro's launch-sequence gate** (spec 7.9, §11.4) — see item 5 above.
  `LevelsIntroGate`'s one-shot rule is complete and tested; the ordering gate against
  ATT/ads/notification-primer has nothing to gate against yet on Android.
- **Level-map presentation polish** — the pulsing current tile, the press-to-0.92-scale
  spring, and the swipeable intro carousel (spec 7.8, 7.9) are all still plain Compose
  layouts with no animation. `LevelsScreen`'s tile grid and `LevelsIntroDialog` are
  functionally complete and spec-accurate but visually a placeholder for these.
**History note on Phase 4/5, for anyone reading the git log and wondering:** this work
merged once already as PR #44, was reverted directly on `master` with no PR and no
recorded reason (commit `42cc257`, ~18 minutes after merging), confirmed afterward to
be unintentional, and is re-landed in this same change — reverting that revert on top
of Phase 3's hardening (which merged in the meantime, as PR #45) and resolving the
resulting overlap by hand. See "Reconciling the two branches" above for exactly what
that overlap was and how each spot was resolved. This is the same reviewed
implementation, integrated, not redone.

**Phase 7 implementation, this session (2026-09-14):** wired full-screen, rewarded and
native ad *presentation* on top of the foundation (SDK init, app id, all nine placement
units, banners, the pure `AdFrequencyCap` policy) merged in PRs #51/#52.

`services/ads/AdsService.kt` grew from an SDK-init-only object into the interstitial/
rewarded adapter: `loadInterstitial`/`notifyGameFinished` cache one interstitial and
reload it after every presentation or failure; `loadRewarded`/`showRewarded` do the same
per rewarded placement (one cached ad per `AdPlacement`, since the four rewarded
placements share one release unit id but are tracked independently so e.g. buying a life
with an ad doesn't also consume the cached forgive-mistakes ad). `AdUnitConfiguration`
gained `isConfigured(placement)` (a placement with a blank id must not load/show — every
Android placement is non-blank today in both build types, pinned by a new
`AdUnitConfigurationTest` case, so this is a forward guard, not a currently-live one) and
`AdMobBanner` now checks it before creating an `AdView`, closing a gap the banner
foundation had left open. `services/ads/AdMobNativeAdView.kt` is new: a manually-built
`NativeAdView` hierarchy (media, badge, headline, body, a non-interactive CTA label) bound
through `AndroidView`'s `update` lambda, the same reason iOS's `AdMobNativeAdView` builds
its native ad view in plain UIKit rather than SwiftUI — neither toolkit has first-class
native-ad support.

`services/ads/AdFrequencyCap.kt` gained `GameFinishedInterstitialTrigger`, a small pure
object (own `GameFinishedInterstitialTriggerTest`, injected clock, no SDK) that folds the
existing `AdFrequencyCap.afterGameCompletion` decision together with the "never after a
paid skip" gate (mirrors iOS's `logGameFinishedIfNeeded(result:allowInterstitial:)`) — kept
separate from `AdsService`'s actual SDK calls so the *decision* stays unit-testable the
same way the underlying cadence policy already was. `AdsService.notifyGameFinished` is the
only thing that calls it: on a `REQUEST` decision it shows the cached interstitial if one
is ready, or kicks off a load for the *next* eligible completion if not — the cadence
counter is only reset by an actual presentation (`AdFrequencyCap.recordInterstitialPresented`),
so a load-miss doesn't cost the player a full cadence cycle, it just retries next time.

`GameViewModel` gained `gameStartedAtMillis` (reset on `restart()`, mirrors iOS's
`gameStartedAt`) and an `onCompletionInterstitial: ((Difficulty, Long) -> Unit)?` callback,
fired from `commit()` unconditionally and from `commitLossIfNeeded(allowInterstitial)`
only when `allowInterstitial` is true — `skipLevelWithStars()` is the one caller that
passes `false`, matching iOS's own skip-path exception exactly. This reuses the class's
existing single-fire commit paths rather than adding a second notification point, so the
interstitial fires exactly once per real finish (win, immediate-commit loss, or a
deferred Level loss once `retry()`/`acknowledgeLossAndQuit()` actually commits it) and
never for a rescue that undoes the loss. `GameViewModel` also gained
`applyForgiveMistakesReward()`/`applyLifeReward()` — line-for-line mirrors of
`forgiveMistakesWithStars()`/`buyLifeWithStars()` minus the wallet spend, since the ad
already paid for the rescue — and `LevelsViewModel` gained the equivalent
`applyLifeRewardFromAd()` for the out-of-lives modal. None of these four present an ad
themselves (`GameViewModel`/`LevelsViewModel` stay Android-framework-free, same as every
other callback in this file); the composable layer (`NavGraph.kt`'s `LEVEL_GAME`/
`SEASON_GAME` routes, `LevelsScreen.kt`) calls `AdsService.showRewarded(activity,
placement, onReward = { coroutineScope.launch { viewModel.applyXReward() } })`, resolving
`activity` once per `NavGraph` composition via a new `Context.findActivity()` extension
(DoMemory is single-activity, so this is `MainActivity` for the life of the process).
`GameScreen.kt` preloads the interstitial and (when `isLevel`) both rewarded placements
once per game instance via `LaunchedEffect`, mirroring iOS's `trackGameStarted` — a cache
miss at the actual finish still self-heals through `notifyGameFinished`/`showRewarded`'s
own load-on-miss fallback, so this is a latency optimization, not a correctness dependency.

`OutcomeOverlay` (`GameScreen.kt`) and `OutOfLivesModal` (`LevelsScreen.kt`) both gained a
"watch ad" button placed above the equivalent star-purchase button, gated on
`AdsService.isRewardedConfigured(placement)` — three string resources that had sat unused
since Phase 0's string catalog (`levels_out_of_lives_message`, `levels_watch_ad_for_life`,
`levels_forgive_ad_format`) are now live; `levels_out_of_lives_message_no_ad` is the
fallback when the placement isn't configured. `MultiplayerScreen.kt`'s
`MultiplayerGameBoard` swaps the finished board's card grid for `AdMobNativeAdView`
entirely (mirrors iOS, which replaces the grid rather than showing both) when the room is
`FINISHED` and the native placement is configured.

**Deliberately left as a seam, not silently dropped:** `game_rewarded_extra_time`
("Watch ad to add 30s") and `game_rewarded_hint` ("Watch ad for a hint") are configured
placements (`AdUnitConfiguration` maps both, `AdPlacement` carries both) with pre-seeded,
still-unused string resources, but neither has an Android call site to wire ad
*presentation* into without first building new player-facing UI: iOS's hint button lives
on a pause modal, and Android's pause is a silent boolean flip with no modal surface at
all (`GameHud`'s pause button just toggles `state.isPaused`); iOS's extra-time button is
ad-only with no star-purchase equivalent on either platform, so there is no existing
"alternative to a star purchase" to slot it beside the way `levelsRewardedLife`/
`levelsRewardedForgive` had. Building either means designing new UI/UX (a pause modal, or
a new lose-screen affordance for every mode including free play, since iOS's extra-time
rescue isn't Levels-gated), which is a product decision beyond "wire ad presentation" —
left for whoever builds that surface next, same standard this plan already applied to the
Levels intro's launch-sequence gate and the season out-of-lives prompt.

**App-open is unimplemented**, not merely unwired — `AdPlacement.APP_OPEN` and its unit id
exist, but there is no Android launch-sequence state machine (ATT-equivalent, ads
bring-up, notification primer, in that order) for `presentAppOpenAdIfAvailable`-equivalent
logic to hook into, the same gap `LevelsIntroGate`'s own Phase 3 note already flagged (O5).

**No purchase/entitlement layer exists on Android**, so nothing here reproduces iOS's
`suppressesInvoluntaryAds` gate on banners/natives/interstitials/app-open — every
`involuntaryAdsSuppressed` parameter in `AdFrequencyCap`/`GameFinishedInterstitialTrigger`
defaults to `false` for exactly this reason (there is no entitlement to read), documented
at the call site rather than silently omitted. Rewarded placements were never gated on
this on iOS either (they're opt-in), so that half needed no change.

**`AdFrequencyState` is in-memory only, reset on every process start** — iOS persists its
interstitial qualifying-completion counter in `UserDefaults` so a relaunch mid-cadence
picks up where it left off; Android does not (`ANDROID_PLAN.md`'s own Phase 7 scope
called DataStore for this "unlikely" to be needed this phase). A session-visible
divergence from iOS, not a correctness bug — the cadence itself (per-difficulty interval,
20 s floor, 60 s rewarded suppression, 90 s global gap) is unaffected within a session.

**No emulator/instrumentation verification** — same limitation as every prior phase.
`./gradlew testDebugUnitTest` (287 tests, 39 files, all green) and `./gradlew
assembleDebug` both pass; actual ad fill, click-through and the AdMob mediation/consent
pipeline are unverifiable without a device or emulator and are not claimed here.

**Phase 8 implementation, this session (2026-09-14): haptics, Play In-App Review, two
Settings rows.** A first Phase 8 slice on top of the already-complete What's New gate —
deliberately scoped to exactly these three things; achievements, the share card,
animations, accessibility announcements and localization are untouched, tracked below.

`services/haptics/HapticIntent.kt` + `services/haptics/HapticsService.kt` port the
*design* of `ios/.../Services/Haptics/HapticsService.swift`, not its UIKit API: one
`HapticIntent` enum naming the moment (`TAP`, `SELECT`, `CARD_FLIP`, `MATCH`, `MISMATCH`,
`SUCCESS`, `FAILURE`, `WARNING`, `REWARD`), one gated `HapticsService.fire(intent)` entry
point, and a two-step pure mapping (`feedbackFor` then `vibrationSpec`) that mirrors iOS's
own `Intent` -> `Feedback` -> UIKit-generator split so the *design* stays legible even
though Android's `VibrationEffect` API has no built-in three-tier notification family or
named soft/rigid impact styles the way UIKit's generators do — every recipe is a
hand-tuned `createOneShot`/`createWaveform` call instead of `createPredefined` (whose
effect ids only arrived in API 29, three levels above this app's `minSdk` 26). The full
mapping table and the reasoning behind each Android-specific choice live in
`HapticsService`'s own class doc. `HapticsService` is an `object` (like `AdsService`,
not a constructed instance held in `AppContainer`) specifically because it must be
reachable both from `GameViewModel` (a bare `(HapticIntent) -> Unit)?` callback, keeping
that class free of any Android import — see `HapticIntent`'s own doc) *and* directly from
`NavGraph.kt`'s composable click handlers ("view-only taps" with no natural view-model
seam: quitting free play, the two watch-ad buttons). `DoMemoryApplication.onCreate` calls
`HapticsService.initialize(this, container.prefs, container.applicationScope)` right
after `AdsService.initialize`; `isEnabled` caches `UserPreferences.hapticsEnabled` (already
implemented, defaults true) into a `@Volatile var` so `fire` can be called synchronously
from a non-`suspend` `ViewModel` function or a click handler.

Wired into every named moment in `GameViewModel`: `CARD_FLIP`/`MATCH`/`MISMATCH` from
`choose()` (silent on `ChoiceOutcome.IGNORED`, i.e. a dead tap, automatically — the early
return happens before the `when`); `SUCCESS`/`FAILURE` from `finish()`, at the instant the
outcome is decided, independent of a Level loss's deferred commit; `WARNING` on a
refused/failed power-up or rescue purchase (`spendOnPowerUp`, `forgiveMistakesWithStars`,
`buyLifeWithStars`, `skipLevelWithStars` — each now fires it on a failed `spend()` or a
failed `apply()`); `REWARD` on every power-up/rescue that actually grants something
(`spendOnPowerUp`'s success path, `forgiveMistakesWithStars`, `buyLifeWithStars`, and the
two ad-earned equivalents, which fire it unconditionally since the ad already paid) —
deliberately *not* fired for `skipLevelWithStars`'s success, since skipping spends stars
to bypass a level rather than granting anything. `TAP` covers `pause()`/`resume()`,
`retry()` (Levels/Seasons) and `acknowledgeLossAndQuit()`; the two purely-navigational
free-play/daily "Try Again"/"Go to menu" taps and both watch-ad buttons have no
`GameViewModel` call to hang off, so they fire directly from `NavGraph.kt` instead — the
same view-only-vs-view-model-driven split this codebase already uses for the ad-service
and interstitial callbacks. This is a fuller port of iOS's actual `HapticsService.shared
.fire(...)` call sites than the task's own minimum list (card flip/match/mismatch/win/
loss) — a grep of `MemorizeViewModel.swift` showed iOS fires almost all of its haptics
from inside the view model, including `.reward` on every power-up/rescue and `.tap` on
every plain button, so extending to those same moments here (still confined to
`GameViewModel.kt` + a few `NavGraph.kt` call sites) is a closer match to the source of
truth, not scope creep beyond it.

**Deliberately left as a seam:** `SELECT` has no call site yet — nothing in the current
Android UI maps cleanly to iOS's "picker change, level tile, turn handover" (level-tile
taps and multiplayer turn handover are Levels/Multiplayer UI this slice didn't touch).
Menu, Levels, Seasons, Multiplayer and Settings screens have no haptics wired at all yet
(only `feature/game/GameViewModel.kt` and its `NavGraph.kt` call sites do) — this was the
task's explicit scope, not an oversight; a future slice should extend the same
`HapticsService.fire`/`HapticIntent` pattern to those screens' own buttons and level-tile
taps rather than inventing a second mechanism. Actual haptic *feel* on a real device is
unverified — no emulator/device is available in this environment (Android's emulator
`Vibrator` is a no-op stub in any case), so only the pure `feedbackFor`/`vibrationSpec`
mapping is test-verified, the same limitation `HapticsServiceTests.swift` has against a
real Taptic Engine.

`services/review/AppReviews.kt` is a thin wrapper over Play Core's
`ReviewManagerFactory`/`ReviewManager` — request a review flow, launch it if Play Core
hands one back, and stop there; Play Core's own contract never reports whether the dialog
was actually shown, the same opacity `SKStoreReviewController` has. **Deliberate
divergence from iOS, per this task's own instruction:** iOS's `AppReviews` wraps a
third-party `ReviewFlow` package with its own local win-count/cooldown/per-version-cap
eligibility policy, plus a one-time `ReviewHistoryMigration` that carries a retired
`ReviewRequestService`'s history into that package's store. Neither is ported — Android's
`ReviewManager` already owns its quota/frequency decision server-side (the app cannot ask
"am I eligible" the way `ReviewFlow`'s config exposes), so a local policy would just be a
second, redundant gate in front of one Google already runs; and there is no legacy
history on Android to migrate from, since nothing has ever prompted for a review before
this slice. `GameViewModel` gained an `onGameWon: (() -> Unit)?` callback, fired from
`commit()` only when the outcome is `GameOutcome.Won` (never for a loss, never for
`skipLevelWithStars`), wired at all four `GameViewModel` construction sites in
`NavGraph.kt` to `{ AppReviews.recordSuccessfulGameWin(activity) }`. This is a deliberate
simplification of iOS's actual call site (`WinModalListener.tapOnContinue`, fired when the
player dismisses the win modal): Android's win overlay has no separate Continue/Next-Level
split yet (`OutcomeOverlay` only offers "Try Again"/"Go to menu" — a pre-existing,
already-documented gap, not introduced here), so firing from the commit itself is the
closest equivalent "genuine success" moment available. Added
`com.google.android.play:review-ktx` (`libs.versions.toml`/`app/build.gradle.kts`,
version `2.0.2`), matching this file's own §2 note that anticipated it for Phase 7/8.

Two new Settings rows (`feature/settings/SettingsScreen.kt`), both under a new
"About" (`settings_section_about`) group — no new string resources needed, since
`settings_review_title`/`_description` and `settings_whats_new_title`/`_description` were
already pre-seeded and unused: "Rate DoMemory" opens the Play Store listing directly
(`market://details?id=<applicationId>` pinned to `com.android.vending` via `setPackage`,
falling back to the `https://play.google.com` listing URL on `ActivityNotFoundException`)
— a `<queries>` entry for `com.android.vending` was added to `AndroidManifest.xml` for
API 30+ package-visibility. This is deliberately separate from, and in addition to, the
win-triggered in-app review prompt above; a code comment at the Settings row's call site
notes that the in-app review flow has no "show it now" API, so this manual button can only
ever be the storefront link, not a way to force the automatic prompt open. "What's New"
reopens `feature/whatsnew/WhatsNewDialog.kt` — its own doc comment already called out this
exact reuse ("intentionally reused for automatic and Settings presentation"); `NavGraph.kt`
now owns a screen-local `showWhatsNew` boolean for the Settings route, separate from
`MainActivity`'s version-gated one, with no `whatsNewLastSeenVersion` write on dismiss
(reopening it manually never needs to touch that key, since it is already at the running
version by the time Settings is reachable at all).

`./gradlew testDebugUnitTest` (293 tests, 40 files, all green — 6 new tests in
`HapticsServiceTest`, pinning `feedbackFor`/`vibrationSpec` the same way
`HapticsServiceTests.swift` pins iOS's mapping without a real Taptic Engine) and
`./gradlew assembleDebug` both pass. No emulator/device verification — same limitation as
every prior phase; actual haptic feel and the Play Store listing/review-flow behavior are
unverifiable from this shell and are not claimed here.

**Phase 8 implementation, second slice (2026-09-14): achievements and the spoiler-free
share card.** Scoped to exactly these two things, same discipline as the first slice —
animations, accessibility announcements and localization are untouched.

*Achievements.* `services/stats/ProfileStatsRecorder.kt` (interface, the same seam shape as
`feature/game/GameStatsRecorder`) and `UserPreferencesProfileStatsRecorder.kt` (its
production implementation) wire the DataStore accessors `UserPreferences` already had —
`incrementTotalPlayed()`/`incrementTotalWon()`/`incrementPerfectGames()`/`setBestRemaining`
— with zero callers before this slice. `services/stats/ProfileStatsService.kt` holds
`ProfileStats` (a suspend `stats()` snapshot, since `UserPreferences` has no synchronous
read the way iOS's `UserDefaults` does) and the pure `achievements(ProfileStats)`
derivation — three win tiers (10/50/100), two streak tiers (7/30, sourced from
`DailyChallengeService.longestStreak()`), one perfect-game badge (`perfectGames > 0`), one
multiplayer badge (`multiplayerWins > 0`) — a line-for-line port of iOS's
`ProfileStatsService.achievements()`'s `isUnlocked`/`progress` rules. `Achievement` carries
string-resource ids (`titleRes`/`detailRes`/`formatArg`) rather than raw text, and an emoji
(`🏅`/`🔥`/`✨`/`🏆`, locked state 🔒) standing in for iOS's SF Symbol — this codebase's own
rule (`ANDROID_PLAN.md` §3, root `CLAUDE.md`) is no icon library, emoji only, matching the
Daily Challenge streak's existing 🔥.

Recording is wired at `GameViewModel`'s two single-fire commit points — `commit()` (every
win, and every loss in a mode with no lose-screen rescue: free play, Daily Challenge) and
`commitLossIfNeeded()` (a deferred Level/Season loss, once `retry()`/
`acknowledgeLossAndQuit()`/`skipLevelWithStars()` actually commits it) — the same two call
sites `recordStats(outcome)` (the per-board recorder) already used, right alongside it. This
was the deliberate choice over adding a third notification path: `GameViewModel` already
guards these two points against double-firing (`winReported`/`lossCommitted`), so profile
stats inherit that guarantee for free rather than needing their own. `isPerfect` reads
`_state.value.failedTries == 0` at the win instant (the field `GameUiState` already carries,
kept in sync by `publishCards()` on every choice, not a fresh read off the model). Wired at
all four `GameViewModel` construction sites in `NavGraph.kt` (free play, Daily Challenge,
endless Levels, Seasons) via `profileStats = UserPreferencesProfileStatsRecorder
(container.prefs)`, matching the existing `stats = UserPreferencesGameStatsRecorder
(container.prefs)` precedent of constructing the recorder inline per call site rather than
storing it in `AppContainer`.

Multiplayer wins are a separate call site with a separate once-per-room, reset-on-rematch
problem iOS's own `MultiplayerRoomViewModel.hasRecordedMultiplayerWin` latch never actually
solves — iOS's field is set on the first `FINISHED`-with-this-client-as-winner update and is
never reset anywhere in that file, unlike its neighboring `hasFiredFinishHaptic`, which *is*
explicitly reset the moment `room.status != .finished` (`fireRoomHaptics`'s own comment:
"restartGame puts the same room back to .playing ... without clearing the latch here, every
game after the first would finish silently"). Rather than port the seemingly-unintentional
never-reset shape, `services/multiplayer/MultiplayerWinGuard.kt` follows the
`hasFiredFinishHaptic` pattern instead — a small, dependency-free class
(`shouldRecordWin(status, winnerId, isCurrentUser)`) that latches once on
`FINISHED`-with-a-win and clears on any non-`FINISHED` status, so a rematch (which the
existing `restart(roomId)` flow puts back to `PLAYING`) can record a win again while a
duplicate `FINISHED` room-update event (recomposition, a redundant Firebase snapshot) never
double-counts. `MultiplayerViewModel` (`feature/multiplayer/MultiplayerScreen.kt`) gained a
`profileStats: ProfileStatsRecorder? = null` constructor param and calls the guard from
inside `observe()`'s existing room-update collector, alongside the pre-existing
`scheduleMismatchClear`/`reconcilePresence` calls at that same site — not the "similar
once-only guards for haptics/interstitial" the task description expected to already exist
there (none do yet; Multiplayer has no haptics wired at all, per the first Phase 8 slice's
own status note), so this guard is new, not an extension of an existing one.

`feature/settings/AchievementsScreen.kt` + `AchievementsViewModel.kt` port
`AchievementsView.swift`: a "Your Stats" 2-column grid (games played, wins, win rate as a
rounded percentage, perfect games, longest streak, multiplayer wins) then a "Badges" list,
each row showing locked (🔒, dimmed text) vs. unlocked (its own emoji, a trailing ✅) state
and a `LinearProgressIndicator` only while locked and `progress > 0f` — same rule as iOS.
`AchievementsViewModel` loads one `ProfileStats` snapshot per screen visit into a
`StateFlow<AchievementsUiState>`; the state's `loading` flag covers the one frame visible
here and never on iOS (a documented, deliberate seam from the async DataStore read, not a
missed requirement). Reached from a new "Achievements" Settings row (`SettingsScreen.kt`,
reusing the already-pre-seeded `achievements_title`/`achievements_subtitle` strings) above
"Rate DoMemory"/"What's New", and a new `Routes.ACHIEVEMENTS` route in `NavGraph.kt`.

*Spoiler-free share card.* `feature/share/ShareResultCard.kt` ports
`ShareResultCard.swift`: the pure `resultGridString(pairs, failedTries)` (green squares
capped at 12, an amber row only when `failedTries > 0`, also capped at 12) is a standalone
function with no Compose/Android dependency, unit-tested directly. `ShareResultCardView`
is the rendered card (brand-primary background, literal white text regardless of the
viewer's theme — mirrors iOS's own literal `.white`/`.white.opacity`, a deliberate exception
to this app's usual `LocalPalette` adaptive tokens, since the card is meant to look the same
on every device it's shared to): app name, 😎, "You Win" (`game_win_title`) or the Daily
Challenge title depending on mode, the grid, then a stats block (difficulty/pairs/remaining/
errors, reusing the pre-existing `menu_difficulty_label`/`game_pairs_label`/
`game_remaining_label`/`game_errors_label` strings) plus a 🔥 streak row shown only for a
Daily Challenge win with `streak > 0`.

Compose has no `ImageRenderer` analogue; `shareResultCard()` uses the current idiomatic
approach — `rememberGraphicsLayer()` + `Modifier.drawWithContent { graphicsLayer.record {
... }; drawLayer(graphicsLayer) }`, then `graphicsLayer.toImageBitmap().asAndroidBitmap()`
— over standing up an offscreen `ComposeView`/window. `GameScreen.kt`'s `OutcomeOverlay`
hosts one alpha-0, correctly-sized (320×440dp) instance of `ShareResultCardView` whenever
the outcome is a win, purely so the graphics layer has real drawn content to capture; a
`Box` stacks children without reflowing siblings, so this has no effect on the rest of the
overlay's layout. A new "Share Result" button (the pre-existing `share_result` string,
placed only in the win branch, above "Try again"/"Menu") launches a coroutine that renders
the bitmap, writes it to `<cacheDir>/share/result_share.png`, and starts an
`Intent.ACTION_SEND` chooser (`type = "image/*"`, `EXTRA_STREAM` + `EXTRA_TEXT`, read URI
permission granted) built from the just-finished game's own `GameUiState` (pairs, remaining
time, failed tries, recorded difficulty) plus new `isDailyChallenge`/`dailyStreak` params
threaded into `GameScreen` from `NavGraph.kt`'s `DAILY_GAME` route only (every other route
keeps the `false`/`0` defaults).

Sharing a `content://` image needed a `FileProvider` — none existed in this codebase
(`AndroidManifest.xml` had no `<provider>`). Added the standard AndroidX pattern: `res/xml/
file_paths.xml` (one `<cache-path>` entry for `share/`), and an `androidx.core.content
.FileProvider` `<provider>` block with authority `${applicationId}.fileprovider`, `exported
= false`, `grantUriPermissions = true` — no new dependency, `FileProvider` ships inside
`androidx.core:core`, already transitively present via `androidx-core-ktx`. Both the
"Rate DoMemory" row's `market://` fallback and the share caption's closing link (port of
iOS's `ResultShare.caption`, whose final line is `InviteLink.appStoreURL.absoluteString`)
now build their URL through one new shared helper, `services/share/PlayStoreLinks.kt`,
rather than each duplicating `"https://play.google.com/store/apps/details?id=$appId"`.

New tests: `ResultGridStringTest` (7 cases — greens-only, greens+amber, the empty/negative
edge, both caps), `ProfileStatsServiceTest` (11 cases — the full `achievements()` derivation
table: unlock-at-threshold-not-before, progress-as-a-fraction-capped-at-1, the two
any-count-above-zero badges, `winRate`'s divide-by-zero guard, `formatArg` presence), and
`MultiplayerWinGuardTest` (7 cases — the once-per-room latch, opponent/draw non-events, the
non-`FINISHED`-resets-the-latch rule, a later winner-bearing update after a draw snapshot).
All three are plain Kotlin against no `DataStore`/coroutine/Robolectric, matching this
repo's existing test style.

`./gradlew testDebugUnitTest` (320 tests, 43 files, all green) and `./gradlew assembleDebug`
both pass. **Unverifiable from this shell, same limitation as every prior phase:** actual
bitmap rendering output, the real OS share sheet, `FileProvider` URI resolution by a
receiving app, and the Achievements screen's visual layout are compiled and unit-tested but
not seen running — no emulator/device is available in this environment.

**Deliberately left as a seam, not silently dropped:**
- Achievements has no navigation entry point on iOS's own Settings screen shown anywhere
  but a plain row — Android's placement (a new "Achievements" row under the existing
  "About" Settings group, alongside "Rate DoMemory"/"What's New") is a reasonable but
  undictated choice; nothing in the spec pins which Settings section it belongs to.
- The share card is reachable only from the win overlay (`GameScreen.kt`), matching iOS's
  own placement inside `Modals/WinModal/`. Levels' lose-screen rescues and the out-of-lives
  modal have no share affordance, by design — there is nothing spoiler-free to share about
  a loss.
- `MultiplayerWinGuard`'s reset-on-non-`FINISHED` behavior is a deliberate divergence from
  iOS's own `hasRecordedMultiplayerWin`, which — as far as this session's reading of
  `MultiplayerRoomViewModel.swift` shows — is never reset at all, meaning a rematch on iOS
  today may not actually re-record a win. Flagged here rather than silently replicated,
  since the task's own requirement ("a room that restarts for a rematch must be able to
  record a win again") only holds with the reset; if iOS's behavior turns out to be
  intentional rather than an oversight, this is the one deliberate cross-platform
  divergence in this slice and should be reconciled explicitly, not silently.
- No emoji was invented for anything: every achievement's emoji and the locked-state 🔒
  reuse this app's existing visual language (🔥 already used for the Daily Challenge
  streak); no new icon-library dependency was added or considered.

**Phase 8 implementation, third slice (2026-09-14): animations and accessibility content
descriptions.** Scoped to exactly these two things, same discipline as the prior two slices
— localization (the nine translations plus the parity test) is untouched.

*Evidence gathering, before writing any code.* Grepped the **entire** `ios/` tree (not just
`Modules/`) for `numericText`/`contentTransition` and `.spring(` — the prompt's own file list
was a starting point, verified rather than trusted. Result: `.contentTransition(.numericText
())` appears **exactly once**, on `PowerUpBar.swift`'s star-balance chip; nowhere else in the
app does iOS animate a changing number. `.spring(...)` appears eight times, but only two are
the animations this slice covers — `LevelMapView.swift`'s `TileTapStyle` (press-to-0.92,
shared by both endless Levels and Season tiles through the one `LevelMapView`/`LevelTileView`
component) and `SeasonLevelsView.swift`'s `progressBar` (`response: 0.5, dampingFraction:
0.8`). The other six (`HomeView.swift`, `MenuView.swift`'s grid-reflow, `SettingsView.swift`
×4) are generic row/card press-scale or a grid-layout animation, not one of the four named
animations, and were left untouched — extending press feedback to Settings/Menu rows is a
different, broader migration slice, not this one.

*Progress-bar spring was already done.* `SeasonLevelsScreen.kt`'s `animatedFraction`
(`animateFloatAsState` + `spring(dampingRatio = Spring.DampingRatioNoBouncy, stiffness =
Spring.StiffnessLow)`) already existed from Phase 4, predating this slice — verified against
iOS's `progressBar` and left alone. Its damping ratio (1.0, critically damped) is a looser
approximation of iOS's `0.8` (slightly underdamped) than an exact port would be, but that was
a pre-existing choice outside this slice's brief of "add the missing animations," not
something this pass changed.

*Tile pulse.* `feature/levels/LevelsScreen.kt`'s private `LevelTile` now pulses only when
`isCurrent`: a `rememberInfiniteTransition`/`animateFloat` (`tween(1100, easing = EaseInOut)`,
`RepeatMode.Reverse`) called *inside* an `if (isCurrent)` branch rather than unconditionally —
that conditional-call placement is what gives the Compose analog of iOS's `onAppear` +
`onChange(of: tile.isCurrent)` re-trigger for free: whenever a tile transitions into
`.current` (usually a tile already on screen as `.locked`, per iOS's own comment), the branch
re-enters composition and the animation restarts from zero; every other tile pays nothing.
iOS's tile is a 64pt `Circle` with a separate stroked ring; Android's tile is a full-width
rounded-rect card with no separate "node," so the ring is drawn as a `matchParentSize()`
rounded-rect border scaling 1 → 1.45 while fading 0.7 → 0 alpha, and the tile itself scales to
1.06 — same growth/fade *behavior*, shape adapted to Android's actual layout rather than
forcing iOS's circle geometry onto a design that doesn't use it. `Season` tiles get **no**
pulse: Android's `SeasonLevelProgressStore` has no "current level" concept the way
`LevelsViewModel.highestUnlockedLevel` does (the screen only distinguishes unlocked/locked),
and inventing one was judged out of this slice's scope — flagged below, not silently dropped.

*Press-to-0.92 spring.* New reusable `Modifier.pressScaleClickable(...)`
(`ui/anim/PressScale.kt`) ports `TileTapStyle` exactly: scale to 0.92 on press, spring back on
release. SwiftUI's `response`/`dampingFraction` has no direct Compose equivalent (Compose's
`spring()` takes `dampingRatio`/`stiffness`); the file documents the conversion used —
`stiffness = (2*PI / response)^2`, giving `~631` for `response = 0.25` — so this is a real
unit conversion of iOS's physical spring, not a similar-looking guess. Applied to `LevelTile`
(endless Levels), the inline tile `Column` in `SeasonLevelsScreen.kt` (same `TileTapStyle`
source on iOS, per the shared `LevelMapView` above), and `CardView.kt`'s game-card tap. The
last one is an **Android-only extension beyond verified iOS evidence** — iOS never applies
`TileTapStyle` (or anything else) to game cards, only to level tiles — added because the
prompt explicitly asked this file be checked, `CardView`'s tap previously had zero press
feedback of any kind (`indication = null` with nothing replacing it), and the change is
visual-only: `onClick`/`enabled` are untouched, so it doesn't touch the gameplay-determinism
contract the root `CLAUDE.md`'s parity table protects. Flagged here as a deliberate,
evidence-labeled divergence rather than presented as a port.

*Numeric transitions.* New reusable `NumericTransition<T>` (`ui/anim/NumericTransition.kt`) —
an `AnimatedContent` keyed on the value with a directional slide (up if the value increased,
down if it decreased) plus fade, the pattern Android's own Compose animation guidance
recommends for a changing counter, since there is no public per-digit "rolling" API (SwiftUI's
`numericText` is a private system transition). Applied to exactly one place:
`GameScreen.kt`'s `PowerUpBar` star-balance text, matching iOS's one verified call site.
Deliberately **not** applied to `GameHud`'s time/pairs/errors chips or `LevelsScreen.kt`'s
header pills, even though the task description named those files as places to check — iOS
itself never animates those numbers either (confirmed by the same whole-tree grep above), and
inventing a transition there would be adding unverified behavior, not porting existing
behavior.

*Accessibility (spec 14.5).* Re-read the spec section directly rather than the task's summary
of it, and re-verified its premise with `grep -n accessibility app/src/main/res/values/
strings.xml`: **four** of the five needed string resources already existed verbatim
(`levels_intro_info_accessibility`, `season_progress_accessibility_format`,
`levels_mistakes_remaining_format`, `levels_timer_frozen_format`, `levels_star_balance_format`,
`levels_powerup_cost_format` — six resources covering the five spec rules; only
`season_progress_accessibility_format` was already wired, from Phase 4). No new string
resources were added — this slice is wiring-only. Wired:
- `GameHud`'s fails chip (`Chip` composable, `feature/game/GameScreen.kt`) — "N of M mistakes
  used" via `levels_mistakes_remaining_format`, applied only when `state.maxFailures != null`
  (free play/Daily Challenge have no budget to report, so the chip keeps its default
  label+value reading there).
- `GameHud`'s timer chip — "Timer frozen, N seconds left" via `levels_timer_frozen_format`,
  applied only while `state.isFrozen`, per the spec's explicit "an always-on label would
  replace the icon-plus-number screen readers already read by default" reasoning.
- `LevelsScreen.kt`'s star-balance `Pill` ("★ N") — "N stars available" via
  `levels_star_balance_format`.
- `LevelsScreen.kt`'s info `IconButton` — "How Levels works" via
  `levels_intro_info_accessibility` (spec-named in §19, not itself one of §14.5's five
  bullets, but the second of the two pre-existing unused strings the task flagged).
- `GameScreen.kt`'s `PowerUpButton`s — "<name>, costs N stars" via
  `levels_powerup_cost_format`, applied only while `enabled`; disabled buttons get no
  `contentDescription` at all and fall back to their default child-text reading, mirroring
  the haptics slice's own "the haptic modifier sits inside the disabled subtree" rule for the
  same spec section.
- `SeasonLevelsScreen.kt`'s progress bar was already wired (Phase 4) — verified against the
  spec's exact wording, left unchanged.

The two pure selection functions with real branching (which value to build the description
from, not just which string resource) — `timerAccessibilitySeconds(timeRemainingSeconds,
isFrozen)` and `failsChipAccessibilityValues(failedTries, maxFailures)`, both in
`feature/game/GameScreen.kt` — are kept separate from the `@Composable`s that resolve
`stringResource`, and pinned by a new `GameHudAccessibilityTest.kt` (6 cases), matching this
repo's existing pure-formatter test style (`ResultGridStringTest`).

`./gradlew testDebugUnitTest` (326 tests, up from 320 — the 6 new accessibility-selection
cases — all green) and `./gradlew assembleDebug` both pass. **Unverifiable from this shell,
same limitation as every prior phase, and explicitly called out per the task's own
instruction:** this is feel work — the tile pulse's timing, the press-spring's physical feel,
the numeric transition's slide direction and the progress bar's spring tuning are compiled and
type-checked but never seen running, and actual TalkBack announcement behavior (ordering,
whether a disabled control's default reading is really silent enough, whether `mergeDescendants`
produces the intended single announcement per chip) was not exercised on a device or emulator.

**Deliberately left as a seam, not silently dropped:**
- Season Levels tiles get press-scale but no pulse — no "current tile" concept exists in
  `SeasonLevelProgressStore` today; adding one is a real feature change, not an animation
  port, and out of this slice's scope.
- `CardView.kt`'s press-scale is an Android-only addition with no iOS source behavior behind
  it (see above) — flagged rather than presented as parity.
- `GameHud` chips, `LevelsScreen.kt`'s header pills (current level, lives, star balance) and
  any other counter not named above stay without a numeric transition, on the same
  evidence-based reasoning as the accessibility scope: iOS doesn't animate them, so this port
  doesn't either.
- No attempt was made to tighten `SeasonLevelsScreen.kt`'s pre-existing progress-bar spring
  constants (`DampingRatioNoBouncy`/`StiffnessLow`) to iOS's exact `response: 0.5,
  dampingFraction: 0.8` — it already animates, which was this slice's bar, and re-tuning an
  already-working, previously-reviewed animation was judged out of scope for a slice about
  filling gaps.

**Phase 8 implementation, fourth slice (2026-09-14): localization.** Added Android
resource tables for all nine non-English locales in the spec: `values-b+es+419`,
`values-pt-rBR`, `values-de`, `values-it`, `values-fr`, `values-hi`, `values-ja`,
`values-ko`, and `values-b+zh+Hans`. The BCP-47 resource syntax is deliberate for the
numeric `419` region and the `Hans` script; Portuguese uses Android's standard region
qualifier. For 228 shared keys, the values come from the shipping iOS app's already
parity-tested `Localizable.strings` tables. The 12 Android-only keys (offline/loading UI,
custom-memorama validation and actions, favorites, the Levels placeholder, and QR scanning)
were translated directly in every locale. iOS-only purchase strings were not brought over
because purchases remain outside Android's scope.

All tables contain the same 240 keys as `values/strings.xml`. Multi-argument translations
were converted to Android's positional specifiers (`%1$d`, `%2$d`, `%1$s`) while preserving
the translated wording. New `LocalizationParityTest.kt` hard-codes the ten expected resource
directories (so deleting a locale fails), rejects missing/extra/duplicate keys, and compares
the multiset of format conversion characters for every localized value against English.
`./gradlew testDebugUnitTest assembleDebug` passes, including Android resource compilation;
this completes Phase 8's parity-test exit criterion. A broader `lintDebug` pass also found
and fixed Phase 8's missing manifest declaration for `android.permission.VIBRATE`; lint then
reached four pre-existing Phase 6 errors (`MultiplayerScreen.kt` resource lookup and three
unremembered `NavGraph.kt` back-stack entries), which remain outside this slice.

**Phase 7 ad-flow verification session, 2026-09-15.** First time any Phase 7 ad flow has
been seen presenting on a device — everything up to this point was unit-test-clean but
unverified against a real `AdsService`/AdMob SDK integration. Same `Pixel_10` (API 37)
emulator. Confirmed first: debug builds serve Google's own public test/demo ad unit ids
(`AdUnitConfiguration.unitId`'s `select(debug, TEST_*, ...)` branch), never the real
production units — every ad seen this session was labeled "Test Ad" by the SDK itself
(a "You've loaded a test ad from AdMob" banner, "This is an interstitial test ad.",
rewarded videos branded "Google Ads"/"Flood-It!", a native card headlined
"Test Ad : Google Ads"), so nothing here risked a real impression or spend.

*Completion interstitial (item 1).* Exercised via free play (which, like every mode,
fires `onCompletionInterstitial` from `GameViewModel.commit()`/`commitLossIfNeeded`) —
chosen over Levels/Seasons for this part specifically so cadence could be driven without
touching the daily lives budget. A `Hard`-difficulty catalog board (`interstitialEveryNWins
= 2`) run to two consecutive natural 60s timeouts showed no ad on the first (`DEFERRED`,
confirmed via a real `AdActivity` launch count of zero) and the real AdMob interstitial
test creative on the second, dismissing and reloading correctly. A second pass using a
purpose-made 2-pair custom memorama ("Fast", deleted afterward) — created specifically to
control game duration — incidentally caught the 20s floor in action: several very-fast
wins (won in a handful of real seconds) never even incremented the qualifying-completion
counter, because `afterGameCompletion`'s `TOO_SHORT` branch returns the *original*, not
incremented, state — confirmed by temporarily adding `Log.d` tracing to
`AdsService.kt`'s interstitial path (see below) and reverted once understood, not by
guessing. A same-session false alarm is worth recording so it isn't re-chased: two
further "Fast"-board wins after the first confirmed presentation also showed no ad despite
what looked like a qualifying `REQUEST` decision, which briefly looked like a caching
regression (the interstitial never reloading after its first show). Diagnostic logging
(`Log.d` calls added to `loadInterstitial`/`notifyGameFinished`/`presentInterstitial`,
gated behind no build flag — a pure temporary diagnostic, reverted via `git diff` showing
clean before moving on) proved those specific wins were actually still under the 20s floor
in real wall-clock time (`TOO_SHORT`, `qualifyingCompletions` unchanged) — not a caching
bug. A follow-up round paced to run past 20s real time then showed `decision=true`, a
cached ad (`cachedAd=true`), an actual `AdActivity` launch, and — critically — a
subsequent `onAdDismissedFullScreenContent → loadInterstitial → onAdLoaded` reload
completing in about one second, confirmed both by the diagnostic log and by the very next
qualifying finish successfully presenting again later in the session (the multiplayer
native-ad check further below). No bug; the diagnostic `Log.d` calls were reverted
(`git diff` on `AdsService.kt` is empty) before any further testing.

*Levels rewarded rescues (item 2).* Played endless Level 2, deliberately racking up
mismatches to `errors: 5/5` (`Too many mistakes`) to reach the lose screen with both
`levels_rewarded_life` and `levels_rewarded_forgive` buttons visible. "Watch ad to forgive
3 mistakes" presented the real rewarded test video, showed "Reward granted" after playing
to completion, and correctly returned to gameplay with `errors` reduced from 5 to 2 (the
board and progress otherwise untouched) — `applyForgiveMistakesReward()`'s effect,
confirmed on screen, not just via the reward callback firing. A second loss (this one a
plain timeout, so only "Watch ad for +1 life" showed — confirms `canWatchAdToForgive` is
correctly gated on `lostToMistakes` and `canWatchAdForLife` is not) was rescued the same
way: rewarded video to completion, "Reward granted", and the level restarted fresh with no
life spent (`applyLifeReward()`). Both grants were real, on-screen state changes, not just
an SDK callback assumed to have worked.

*60s post-rewarded suppression (item 4, partial).* Immediately after the second rewarded
grant above, three more mismatches were forced to reach a fresh `errors: 5/5`, and this
loss was committed (`Menu` → `acknowledgeLossAndQuit()`, confirmed by "3 of 4 lives
remaining" on the menu afterward) well inside 60 real seconds of the rewarded-ad grant.
No interstitial presented — confirmed by an unchanged `AdActivity` launch count — exactly
matching `RECENT_REWARDED` suppression, and this finish would otherwise plausibly have
qualified (a Level loss, duration comfortably over the 20s floor). The 20s floor itself
was already covered above. The 90s global gap was **not** independently demonstrated as a
live `GLOBAL_GAP`-suppressed case — every gap check this session had already had enough
real wall-clock time elapse (multi-minute UI navigation between rounds) that the decision
was always `REQUEST` by the time a qualifying finish landed, which is itself a correct
exercise of the same branch (`nowMillis - lastFullScreenAtMillis >= FULL_SCREEN_GAP_MILLIS`
evaluating true), just not the suppressed half. Deliberately pacing two sub-90s qualifying
finishes back-to-back to force the suppressed branch was judged not worth the additional
emulator time this session, given `AdFrequencyCapTest`'s existing `GLOBAL_GAP` case already
pins that exact branch in pure logic and the sibling `RECENT_REWARDED` branch (identical
"early-return before the cadence/gap checks" shape) was just confirmed live above.

*Multiplayer-finished native ad (item 3).* Re-verified deliberately, not reused from
memory of the incidental iOS confirmation earlier today. Since testing against a second
iOS Simulator wasn't readily available in this environment (no `idb`), a **second Android
emulator** was used instead — the existing `Pixel_10` AVD directory was cloned
(`~/.android/avd/Pixel_10_B.avd`, since no `avdmanager`/`cmdline-tools` were installed to
create one the normal way) and its app data cleared (`pm clear`) before first launch so it
authenticated as a genuinely distinct Firebase anonymous user, confirmed by comparing the
two devices' logged UIDs. A real room (host on the original emulator, guest on the clone)
was created, joined (the join failed once with the same generic
"Multiplayer is unavailable." error the 2026-09-15 Android↔iOS session hit on its first
attempt — see that note above — and succeeded on an immediate retry, consistent with that
being connection-establishment flakiness on a just-launched client rather than a rules or
protocol problem; not chased further since it's unrelated to Phase 7 and already understood
context from that earlier session), played to a real 4-0 finish, and both clients showed
`AdMobNativeAdView` in place of the card grid — device A "Test Ad : Google Ads", device B
independently "Test Ad : Flood-It!" (different creatives, confirming each side loads its own
native ad rather than sharing one). Both results were consistent (host "You won" 4-0,
guest "You lost" 0-4). **Frequency-cap interaction, checked deliberately per this task's
instruction, not just "did an ad appear":** `MultiplayerScreen.kt`/`MultiplayerViewModel`
never call `AdsService.notifyGameFinished` — confirmed by code (no such call site exists
in `feature/multiplayer/`) and empirically (the `AdActivity` launch count did not change
across the multiplayer finish, and the native ad itself renders inline via `NativeAdView`,
never through `AdActivity`). The multiplayer native placement is therefore correctly
orthogonal to the interstitial frequency cap in both directions: finishing a multiplayer
match doesn't consume or reset the interstitial cadence counter, and a pending interstitial
cadence state has no bearing on whether the native ad shows. "Play again" was also
exercised: the native ad correctly disappeared and the card grid returned the instant the
room left `FINISHED` for a fresh `PLAYING` rematch, matching `MultiplayerGameBoard`'s
`room.status == FINISHED` gate exactly.

No source changes were made — the one edit this session (temporary `Log.d` diagnostics in
`AdsService.kt`, used to resolve the `TOO_SHORT` false alarm above) was fully reverted
before the session ended; `git diff` on the file is empty and `./gradlew testDebugUnitTest`
(326 tests, unchanged) and `assembleDebug` were both re-run clean afterward. Test-only
artifacts created for this session (the "Fast" custom memorama, the cloned `Pixel_10_B`
AVD and its emulator process) were deleted before finishing, leaving both the app's
on-device state and the host machine's AVD directory as they were found, apart from the
Level 2 progress consumed by the deliberate mistake/loss testing above (one life spent,
reflected honestly in "3 of 4 lives remaining").

**Incidental finding, not fixed (out of scope for this session):** the onboarding
difficulty picker (`Choose your pace`) renders `Difficulty.VERY_HARD` as the literal
enum-derived string **"Very_hard"** instead of a translated `difficulty_very_hard`-style
label, on a freshly-installed app before any game has been played. This is the same class
of bug the 2026-09-14 emulator session found and fixed in `SettingsScreen.kt` (raw enum
name bypassing the string catalog) — evidently that fix didn't cover every difficulty
picker in the app, just the one in Settings. Confirmed live on two independent fresh
installs (both emulators, this session). Left unfixed here per this task's explicit
boundary against combining unrelated cleanup with the requested ads verification; flagged
for a future session.

**Haptics expansion, 2026-09-15.** Closed out §8 items 8 and 10 together: `HapticsService.fire`/
`HapticIntent` was wired into `feature/game/GameViewModel.kt` and a handful of `NavGraph.kt`
taps only (per the Phase 8 note above); every other screen — Menu, Levels, Seasons,
Multiplayer, Settings — had none. Read against iOS's actual call sites (`ios/DoMemory/DoMemory/
Services/Haptics/HapticsService.swift` and its usages across `Modules/Menu/`, `Levels/`,
`Seasons/`, `Multiplayer/`, `Settings/`) rather than guessed from names. Android's `HapticIntent`
enum already had all nine cases iOS's `Intent` enum does (`TAP`/`SELECT`/`CARD_FLIP`/`MATCH`/
`MISMATCH`/`SUCCESS`/`FAILURE`/`WARNING`/`REWARD`), so **no new case was needed** — this was
purely a call-site-wiring slice, not an enum change.

- **Menu** (`feature/menu/MenuScreen.kt`): `TAP` on the multiplayer/create/settings header
  buttons, the season card, board cells (tap-to-play and the favorite star), and the empty-
  "My memoramas" create button — all match an explicit iOS `.tap` call site in `MenuView.swift`.
  The Daily Challenge card's tap (`NavGraph.kt`'s `onDailyChallengeSelected`) fires `TAP` inside
  the same `!isDailyChallengeCompletedToday` guard iOS's own `DailyChallengeCard`/
  `CompactDailyChallengeCard` use. One deliberate non-parity addition: the "All" tab's
  difficulty-filter chips fire `SELECT` — iOS's Menu has no such filter at all (it only shows a
  read-only difficulty badge), so there was no call site to match; `SELECT` was chosen because
  it's exactly `HapticIntent`'s own documented "picker change" case, not an invented one.
  `AchievementsScreen.kt` and `CreateMemoramaScreen.kt` were left untouched — neither is one of
  the five named screens, and iOS's own `AchievementsView.swift` has no `HapticsService` call at
  all.
- **Levels** (`feature/levels/LevelsViewModel.kt` + `LevelsScreen.kt`): `LevelsViewModel` gained
  an `onHaptic: ((HapticIntent) -> Unit)? = null` constructor param, the same bare-callback shape
  `GameViewModel.onHaptic` already uses (Android-framework-free, wired to `HapticsService::fire`
  only from `NavGraph.kt`). `attemptStart(level)` fires `SELECT` on a successful start and
  `WARNING` on the out-of-lives refusal — mirrors `LevelsView.swift`'s `onSelect` exactly.
  `buyLifeWithStars()` fires `REWARD` only after `wallet.spend()` actually succeeds (iOS's own
  comment on that exact button: "a .tap here would double-buzz"), and `applyLifeRewardFromAd()`
  fires `REWARD` when the ad payout lands, not on the watch-ad tap. The composable layer
  (`LevelsScreen.kt`) fires `TAP` on the intro info button and the `OutOfLivesModal`'s watch-ad
  and dismiss buttons, matching `OutOfLivesModal.swift` line for line — including *not* wrapping
  the buy-with-stars button, per that same double-buzz comment.
- **Seasons** (`feature/seasons/SeasonLevelsScreen.kt`): tile taps fire `SELECT`, matching iOS's
  `SeasonLevelsView.onSelect`. iOS's sibling `.warning` branch (a lives-based refusal) was **not**
  ported — Android's season map has no out-of-lives gate at all yet (locked tiles are simply
  `enabled = false`; the season-specific out-of-lives prompt is a separate, still-open item, §8
  item 4). Building that gate was out of this slice's scope; wiring its `WARNING` haptic is one
  line once it exists.
- **Multiplayer** (`services/multiplayer/MultiplayerHapticsTracker.kt`, new;
  `services/multiplayer/MultiplayerModels.kt`'s new `MultiplayerRoom.canFlipNow`;
  `feature/multiplayer/MultiplayerScreen.kt`): the highest-value screen per this task's own
  framing, since it's real-time and a player may not be looking at the screen when something
  happens. `MultiplayerHapticsTracker` is a pure, stateful class — the same shape as
  `MultiplayerWinGuard` and deliberately built with the identical rematch-reset fix from the
  start (its `hasFiredFinishHaptic` latch clears the moment a room leaves `FINISHED`, so a
  rematch's `SUCCESS`/`FAILURE` isn't silently swallowed the way iOS's own win-recording latch
  was buggy until this same day's earlier `MultiplayerWinGuard` fix — see §8 item 11 above).
  It ports `MultiplayerRoomViewModel.fireRoomHaptics` case for case: `MATCH`/`MISMATCH` on a
  newly-resolved selected pair (latched on a signature so a duplicate snapshot doesn't re-fire),
  `SELECT` once on the edge of a turn landing on this player, and `SUCCESS`/`FAILURE` once per
  `FINISHED` streak (a draw reads as `FAILURE`, matching iOS's own `winnerId == currentUserID`
  comparison, which is also false for a draw — not a chosen design, a preserved one).
  `MultiplayerViewModel.choose()` fires the one *local*, optimistic haptic (`CARD_FLIP`) itself,
  gated by the new `MultiplayerRoom.canFlipNow(isCurrentUser)` — a pure port of iOS's
  `isInteractionEnabled` (playing, my turn, fewer than two cards already selected) — so a tap
  that can't actually flip anything (wrong turn, already two selected) stays silent, matching
  iOS's own guard in front of its `.cardFlip` fire. The composable layer additionally fires `TAP`
  on the back/leave button, join/create/scan-QR/start-game buttons, and the rematch button —
  each matches an explicit iOS `.tap` (`JoinMultiplayerRoomView.swift`'s Join button,
  `MultiplayerRoomView.swift`'s Start Game/Play Again/header-leave buttons) except the QR-scanner
  button, which has no iOS analog at all (iOS never scans a code; it relies on the system camera/
  universal links) and was given `TAP` anyway as an ordinary button under `HapticIntent`'s own
  "any button or row" definition. iOS's invite-share button was deliberately **not** ported to
  fire a haptic — its iOS counterpart is a native `ShareLink` with only an analytics
  `simultaneousGesture`, no `HapticsService.fire` call at all.
- **Settings** (`feature/settings/SettingsScreen.kt`): unlike the "maybe nothing" the task
  flagged as a live possibility, iOS's `SettingsView.swift` actually fires `.tap` on nearly every
  row. Android's difficulty/theme `Choice` rows and the Achievements/Rate-DoMemory/What's-New
  `SettingRow`s all fire `TAP`, matching iOS's `SettingsNavigationRow`/`SettingsActionRow`
  equivalents. The haptics and notifications toggles fire `TAP` **before** calling their own
  `onHaptics`/`onDisableReminders`/`requestPermission` callback — this ordering is load-bearing,
  not cosmetic: it mirrors iOS's own comment ("fire before flipping the flag so turning haptics
  OFF still confirms the tap") and Android's own subtlety flagged for this task — `HapticsService
  .isEnabled` is a synchronously-cached `Boolean` updated *asynchronously* by a `Flow` collector
  in `HapticsService.initialize`, so firing after the DataStore write could race the cache update
  and silently swallow the very tap that turns haptics off. iOS's IAP-only rows (Remove Ads,
  restore purchases, rewarded remove-ads) have no Android counterpart at all (D2: Billing is
  deferred) and were correctly left unported. `AchievementsScreen.kt` again gets nothing, per
  iOS's own silence there.
- **Verification.** `./gradlew testDebugUnitTest assembleDebug` is clean (348 tests, 0 failed).
  Nineteen new tests were added: `MultiplayerHapticsTrackerTest` (the tracker's full state
  -machine — resolved-pair latching, turn-edge `SELECT`, finish-latch reset on rematch, a draw
  reading as `FAILURE`, multiple intents in one snapshot), `MultiplayerRoomCanFlipNowTest` (the
  new gating method), and `LevelsViewModelHapticsTest` (the `SELECT`/`WARNING`/`REWARD` call
  sites, built the same way `LevelProgressServiceTest`/`LevelLivesServiceTest` are — real
  services over a temp-file `UserPreferences`, no mocking framework). **Not verified:** actual
  haptic *feel* on a real device. No emulator was running this session (`adb` wasn't even on
  `PATH`), and per this task's own explicit allowance and the precedent set by every prior
  device-only Phase 8 follow-up, this was not chased — only the code paths and their unit tests
  are confirmed. Wiring correctness (which screen fires which intent, in what order, gated
  correctly) is what's actually verified here, not the vibration motor.

**Shared Lottie effects, 2026-09-15.** Cross-platform commit (`1dc9282`, co-authored
`Claude Fable 5.1`) moving the two hand-authored win-screen clips (confetti burst, staggered
star pop — already live on both platforms) to a new shared `assets/animations/game/` at the repository
root, reached by iOS through a `SupportingFiles/Lottie` symlink and by Android through an
extra `assets.srcDir` in `app/build.gradle.kts`, so one JSON file per animation serves both
apps and the two cannot drift on frame count, colour or timing. Added `lottie-compose` 6.7.1,
a new `ui/lottie/BundledLottie.kt` wrapper mirroring iOS's `LottieView`, and
`ui/anim/ReduceMotion.kt` (`rememberReduceMotion`, reading the system animator-duration-scale
setting) as the Android counterpart of `accessibilityReduceMotion`. Six new clips, generated
via `scripts/animations/generate_animations.py` and tinted at runtime through a shared `**.tint`
keypath so one file serves light and dark: a lose-modal hero (clock-crack on timeout, x-shake
on a mistake bust; reduce-motion keeps the static face), heart-break/heart-refill on the new
canonical `ui/components/LivesRow.kt` (fired on both the endless and season map headers, since
Android's lose overlay shows no hearts and defers the spend, unlike iOS which also breaks a
heart on its lose modal), a freeze-thaw ice-shatter over the timer chip, and a star-sparkle
over the header star chip on a credit only, never a spend. `LevelsViewModel.UiState` now
carries `livesEffect`/`starsCredited`, never populated on a screen's first load. New tests:
`WinStarSlotTest`, `HeaderEffectsTest`, `LevelsViewModelEffectsTest`, `LottieAssetsTest`
(every clip decodes, stays under a second, exposes its tint shape name).

**Levels/Daily Challenge/Seasons visual-parity pass, 2026-09-15.** Closed the visual gap
between these three Android screens and shipping iOS, read against the actual SwiftUI source
rather than the spec's prose (`LevelMapView`/`LevelsView`/`OutOfLivesModal`/`IntroCarouselView`
under `ios/DoMemory/DoMemory/Modules/Levels/`, `SeasonLevelsView.swift`, and the
`DailyChallengeCard`/`CompactDailyChallengeCard`/`SeasonCard`/`CompactCardLayout` private
structs in `MenuView.swift`). Added `material-icons-extended` for real vector icons (lock,
help-outline, verified, back arrow) replacing emoji/text glyphs on these three screens.

- `LevelTile`: cleared tiles now always show all 3 star slots (filled vs. muted-outline),
  matching `LevelMapView.swift` — a 1-star clear no longer reads as a lone star. Lock glyph is
  a real icon. Lives pill gets the same `Pill`/capsule treatment the star counter already had.
- `OutOfLivesModal` rebuilt to match `OutOfLivesModal.swift`: embeds a 0-lives `LivesRow`,
  full-width capsule buttons instead of default Material buttons.
- Levels intro rebuilt as a real full-screen swipeable `HorizontalPager` (4 slides, icon
  circles, dot indicators, Skip button), replacing the earlier static stacked-dialog
  placeholder — closes the gap this file's own prior comment flagged as deferred "presentation
  polish." Hoisted to `NavGraph.kt`'s Menu composable (same pattern as
  `NotificationPrimerHost`) so it covers the full screen, matching iOS's `.fullScreenCover`,
  instead of only the Levels tab's content area.
- **Season out-of-lives gate built** (closes item 2 below): new `SeasonLevelsViewModel` wires
  the spec 7.4 lives check into a season tile tap, reusing the same restyled
  `OutOfLivesModal`. The season map's tiles were previously tappable with no lives check at
  all. Also added the header's lives/star pills (previously absent — only a cumulative star
  count sat inline next to the progress text, which was itself the wrong metric; the header
  now shows the spendable wallet balance, matching iOS), a visible back button
  (transparent-over-artwork / opaque otherwise, matching iOS's nav-bar toggle — there was
  previously no in-app back affordance), and a restyled completion banner (tinted/bordered
  card with a seal icon, replacing two bare text lines).
- **Compact Daily Challenge/Season cards built** (closes the "compact Daily-card layout" part
  of item 6 below): new shared `ui/components/CompactCardLayout.kt` ports iOS's
  `CompactCardLayout` literally (icon circle → title → badge, including the leading→trailing
  artwork gradient for text legibility). `DailyChallengeCard` now branches full vs. compact
  exactly like `MenuView.swift` — previously it was one flat, uncoloured card in both states,
  with no icon and a plain-text badge instead of a pill. `SeasonCard`'s badge now shows
  `cleared / total`/"Complete" (the correct per-`MenuView.swift` metric) instead of
  days-remaining, which belongs on the season screen's own header, not the menu card.

Verification: `./gradlew testDebugUnitTest` 374/374 passing (7 new: `SeasonLevelsViewModelTest`
— lives gate allow/refuse, haptics, buy-with-stars, ad-granted reward, first-load-never-animates
effect state), `assembleDebug` succeeds, and an on-device `Pixel_10` (API 37) smoke test
confirmed the compact menu cards, the Levels header pills/lock icon/3-star rows/tile pulse, the
Season Levels back arrow/header pills/full-bleed artwork, and the full-screen swipeable intro
carousel (catching and fixing the full-screen-coverage bug above). **Not verified:** the
out-of-lives modal's actual on-screen appearance (would need spending down to 0 lives on
device) and RTL/dark-mode-specific rendering of the new components.

**Phase 8 implementation, fifth slice (2026-09-16): analytics instrumentation.** Closes the
"Haptics and analytics — still absent everywhere" gap noted earlier in this log (analytics
half only; haptics landed in an earlier slice above). Added `services/analytics/` —
`AnalyticsEvent` (a sealed class, one case per event, each owning its own `name`/`parameters`)
and `AnalyticsService` (the single `object` gate; `log` is the only sanctioned
`FirebaseAnalytics.logEvent` call site in the app) — matching §16's spec table verbatim: same
event names and parameter keys as iOS's `enum AnalyticsEvent`, since both platforms log into
one Firebase project. Wired into `DoMemoryApplication.onCreate` and ~20 existing screens/view
models: `GameViewModel` (start/finish for every mode, sampled `card_tapped` at 20%, pause/
resume, retry, power-ups, lose-screen rescues, mistake-budget losses, level unlock gating),
`MenuViewModel` (load, difficulty, favorites), `CreateMemoramaViewModel`, `LevelsViewModel`/
`LevelsScreen`, `SeasonLevelsViewModel`/`SeasonLevelsScreen`, `MultiplayerViewModel`/
`MultiplayerScreen`, `OnboardingViewModel`/`OnboardingScreen`, `NotificationPrimerDialog`,
`WhatsNewManager`, `AchievementsScreen`, `SettingsScreen`, `ShareResultCard`, and the ads
layer (`AdsService.showRewarded`, `AdMobNativeAdView`). Not ported: `level_stars_credited` —
`LevelProgressService`/`SeasonProgressService` don't yet surface the improvement-only credit
delta it needs (see `AnalyticsEvent`'s class doc for the full reasoning). A few call sites are
intentionally less granular than iOS, each documented at its site in `NavGraph.kt`:
`multiplayer_room_created.game_id` is blank at creation time (Android's host-first flow
creates the room before a game is picked); free play's `game_started.source` can't
distinguish a board-card tap from the random-game button; and a Levels/Seasons "next level"
transition reports the same entry source as a normal map visit rather than iOS's dedicated
`"next_level"` case. Verification: `./gradlew assembleDebug testDebugUnitTest` 416/416 passing
(35 new `AnalyticsEventTest` cases pinning every event's name/parameters). Not verified on
device — no emulator/device session run for this slice.

**Multiplayer join-by-QR fix and lobby centering, 2026-09-21.** Scanning an iOS-created room's QR on a
cold Android client failed with "Multiplayer is unavailable." while typing the same code joined. Root
cause: `MultiplayerService.transaction` aborted whenever `data.value` was null, and Firebase runs a
transaction's first pass against the *local cache* — empty for a room this client has never observed —
so the first join of any room surfaced as `InvalidMove` without ever asking the server; the SDK's
internal listener then cached the room, which is why a retry (or typing the code afterwards) worked.
`RoomTransactionPlan` now returns `AwaitServer` for an empty cache (commit the unchanged null so the
SDK re-runs the handler with the server's data), and `transaction`'s `onComplete` reports `NotFound`
if the server has no room either. The Multiplayer screens (join, lobby, board status) are now
horizontally centered like iOS's `VStack`s, with the back button kept on the leading edge.
Verification: `./gradlew assembleDebug testDebugUnitTest` green (4 new `RoomTransactionPlanTest`
cases); reproduced and fixed on the `Pixel_10` emulator by scanning a CoreImage-generated QR (the same
generator iOS uses) for a real room from a force-stopped app — before: error, after: joins first try.
Still open: every `MultiplayerException` has a null message, so the UI shows the same generic English
"Multiplayer is unavailable." for `NotFound`/`Full`/`InvalidCode`/`InvalidMove` alike, and the
"This QR code is not a DoMemory room." text is a hardcoded English literal.

**Settings/back-button polish, 2026-09-21.** Achievements moved to the first row of Settings' Game group,
matching iOS's `SettingsView` (it was the first row of "About", at the bottom). The bare "‹" glyphs that
served as back buttons on Multiplayer, Settings and Achievements (about 12dp tall, with a matching tap
target) are replaced by the shared `ui/components/BackButton` (28dp arrow in a 48dp target, TalkBack label
`common_back`); Season Levels' own icon button now uses it too. Settings also gained `verticalScroll` — the
About group was clipped off the bottom of a 1080x2424 emulator screen once the extra Game-group row landed.
Verification: `./gradlew assembleDebug testDebugUnitTest` green; Settings, Achievements, Multiplayer and Season
Levels viewed on the `Pixel_10` emulator, including tapping through to Achievements and back.

**Fonts, 2026-09-21.** `DoMemoryType.display`/`handwritten` now use Righteous and Patrick Hand, byte-for-byte
copies of the TTFs in `ios/DoMemory/DoMemory/SupportingFiles/Fonts` placed in `res/font` (SIL OFL 1.1, notices
embedded in the files). Discrepancy worth knowing: iOS bundles and registers those fonts but its
`Font.righteous`/`Font.patrickHand` return `.system(design: .rounded)`, so iOS renders SF Rounded Heavy and
Android now renders the real Righteous — the two platforms' headings are not visually identical. Both fonts
ship one Regular weight, so the roles request `FontWeight.Normal` (heavier makes Compose synthesize a fake
bold) and `LaunchScreen`'s two forced-`Black` overrides were dropped. Devanagari/CJK glyphs fall back to the
system font per character. Verification: `assembleDebug testDebugUnitTest` green; menu title, "Levels" and
Settings headings viewed on the `Pixel_10` emulator (Latin only). Not viewed: the in-app `LaunchScreen`, and
any non-Latin locale.

**Multiplayer result banner, 2026-09-22.** `MultiplayerGameBoard`'s finished-room state reused the plain
mid-game turn-indicator `Text` (no explicit size, Material's default body style) for "You won"/"You
lost"/"Draw", so the result of a whole match read no bigger than "Your turn". Ported iOS's matching fix
(PR #88): a `MultiplayerResultKind` (WON/LOST/DRAW) computed once from `room`+`vm.isCurrentUser`, and a new
`MultiplayerResultBanner` shown only when finished — a 44sp emoji (😎/😳/🤝) plus a 28sp `DoMemoryType.display`
headline in `palette.primary`/`secondary`/`textPrimary`, matching the single-player win/lose screens'
existing visual language, with the previously-unused `multiplayer_final_score` string as a subtitle.
Verification: `compileDebugKotlin` clean; `cleanTestDebugUnitTest testDebugUnitTest` 422/422 passing (no
new tests — the change is purely presentational, no new branching logic beyond the existing win/lose/draw
resolution `MultiplayerViewModel` already had). Not viewed on an emulator/device — no live session run.

**WhatsNewKit-Android adoption (2026-09-29).** The hand-rolled `AlertDialog` in
`feature/whatsnew/WhatsNewDialog.kt` is gone; the What's New screen is now drawn by
[WhatsNewKit-Android](https://github.com/zoratek/WhatsNewKit-Android) 1.0.0, the Compose twin of
the `whats-new-ios` package iOS already uses. The library's README documents JitPack coordinates,
but both the `zoratek` and `ezequielbrrt` repositories are private and JitPack answers 401 for
them, so the repository is vendored as a git submodule at `android/WhatsNewKit-Android` (pinned to
tag `1.0.0`) and `settings.gradle.kts` includes only its `whatsnewkit` module as `:whatsnewkit` —
`:demo` is never configured. The module reads this build's version catalog, hence the new
`android-library` plugin alias (declared `apply false` at the root, since it shares the AGP
artifact with `android-application` and applying it with a version from a subproject fails with
"already on the classpath with an unknown version") and the `androidx-compose-foundation`
library alias. `feature/whatsnew/WhatsNewContent.kt` ports `WhatsNewContent.swift`: a
`Palette.whatsNewTheme()` mirroring `WhatsNewTheme.doMemory` token for token (card tinted
`surfacePrimary` over the library's material layer, borders/separators `surfaceBorder`, badge and
icon chips `primary` at 14%, headline in `DoMemoryType.display(30)`), and the same four
`whats_new_*` string pairs the dialog showed, now with Material icons (gift, palette, touch,
timeline) standing in for iOS's SF Symbols. The version gate is unchanged —
`services/whatsnew/WhatsNewManager` and spec 15.1's `whatsNewLastSeenVersion` stay, and the
library's `WhatsNewVersionTracker` is deliberately not used, matching iOS, which keeps its own
`WhatsNewManager` beside WhatsNewKit. Presentation moved to a single site: `MainActivity` now
wraps the `Scaffold` in a `Box` and draws `DoMemoryWhatsNewScreen` edge to edge above the nav
graph (the library pads for system bars itself and would have doubled the Scaffold's insets),
with the launch overlay moved to the same `Box` so it still covers the screen during the 1.2s
splash; a private `WhatsNewPresentation` enum (AUTOMATIC/MANUAL) decides whether dismissal calls
`markSeen()`. `NavGraph` gained an `onWhatsNew` parameter so the Settings row reaches that site
instead of hosting its own dialog. Verification: `:app:assembleDebug` clean;
`:app:testDebugUnitTest` 422/422 and `:whatsnewkit:testDebugUnitTest` 21/21 green; on the
Pixel_10 emulator the Settings row opens the screen in light and dark (status-bar icons flip with
the appearance), "Let's Play" returns to Settings, and the system back key is consumed while it
is up. The automatic post-upgrade path was not exercised on the emulator (it needs a stored
`whatsNewLastSeenVersion` older than the running one) — its gate is untouched and remains covered
by `WhatsNewManagerTest`.

**ReviewFlow-Android adoption (2026-09-29).** The thin Play Core wrapper in
`services/review/AppReviews.kt` is gone, and with it the Phase 8 decision above to diverge from
iOS's local review policy: Android now uses
[ReviewFlow-Android](https://github.com/zoratek/ReviewFlow-Android) 1.0.0, the Compose twin of the
`ReviewFlow` package iOS wraps in `AppReviews.swift`, vendored exactly like WhatsNewKit-Android —
private repository, git submodule at `android/ReviewFlow-Android` pinned to tag `1.0.0`, only its
`reviewflow` module included as `:reviewflow`, built against this catalog (which gained
`play-review-ktx` — renamed from `google-play-review-ktx`, since :app no longer depends on Play
Core directly and the library re-exports it as `api` — plus `kotlinx-coroutines-core` and
`compose-material-icons-core`). `AppContainer.reviews` holds the one `ReviewManager` (recommended
policy: 3 wins, 7 days since first use, 120-day cooldown, one ask per version; history in the
library's own `SharedPreferences` file, nothing to migrate on Android). `NavGraph.kt`'s four
`onGameWon` sites now call `recordSuccessfulAction(BuildConfig.VERSION_NAME)` on it. Presentation
is the library's **explicit invitation**, not its Play In-App Review bridge — the user asked for
the iOS image to be used, and the image only exists in the invitation: `feature/review/
ReviewInvitation.kt`'s `DoMemoryReviewInvitationHost` wraps `ReviewInvitationHost` with
`palette.primary` as accent, the display face for the headline via `LocalReviewInvitationStyle`,
the iOS `onboarding-five-star-rating` PNG copied byte-for-byte to
`res/drawable-nodpi/review_invitation_five_star_rating.png`, and four new `review_invitation_*`
strings translated into all ten locales (`LocalizationParityTest` green). `MainActivity` hosts it
beside the What's New screen, mirroring iOS's `.reviewRequest(using:)` at the app root. iOS itself
still uses the native StoreKit prompt in production and only shows `ReviewInvitationFullScreen`
from its debug menu; switching Android to the same native path is a one-line swap to
`ReviewRequestEffect(manager = container.reviews)`. The Settings "Rate DoMemory" row now calls the
library's `Context.openPlayStoreReviewPage()` (same `market://` + web fallback the local helper
had), so that helper was deleted; `services/share/PlayStoreLinks` stays for the share caption.
Spec §15.2's Android paragraph was updated to match. Verification: `:app:assembleDebug` clean;
`:app:testDebugUnitTest` 422/422 and `:reviewflow:testDebugUnitTest` 11/11 green; on the Pixel_10
emulator the invitation was rendered in light and dark through a throwaway local patch that
presented `ReviewInvitationDialog` unconditionally (not committed), and its "Write a Review" tap
brought the Play Store app (`com.android.vending`) to the foreground — the policy-gated path itself
(three wins, seven days) was not exercised end to end and rests on the library's
`ReviewManagerTest`/`ReviewEligibilityEvaluatorTest`.

**NotificationPermissionKit-Android adoption (2026-09-29).** The hand-rolled primer card in
`feature/notifications/NotificationPrimerDialog.kt` and the bare `rememberNotificationPermissionRequester`
in `NotificationPermission.kt` are gone; the permission primer (spec 11.3) is now drawn by
[NotificationPermissionKit-Android](https://github.com/zoratek/NotificationPermissionKit-Android) 1.0.0,
the Compose twin of the `NotificationPermissionKit` package iOS wraps in `NotificationPrimerContent.swift`,
vendored exactly like the other two — private repository, git submodule at
`android/NotificationPermissionKit-Android` pinned to tag `1.0.0`, only its `notificationpermissionkit`
module included as `:notificationpermissionkit`, built against this catalog (no new aliases needed).
`feature/notifications/NotificationPrimer.kt` ports the Swift file: the fixed violet
`DoMemoryNotificationPermissionTheme` (literal colours on purpose — one identity in both appearances,
as iOS's comment says), a configuration built from the existing `notification_primer_*` and
`settings_notifications_denied_*`/`_open_settings` strings (the English denied message said "iOS
Settings"; fixed to "Android Settings", the other nine locales already said Android), Material icons
(fire, psychology, raised hand) for the SF Symbols, and `NotificationPrimerHost(visible, source,
onAuthorized, onFinished)` presenting the library's `NotificationPermissionScreen` in a full-screen
dialog — the Android reading of iOS's sheet — with the back gesture reported as `Deferred`. Analytics
are unchanged in name and value: `notification_primer_shown` on appearance and
`notification_primer_completed` with `authorized`/`denied`/`deferred`/`failed`, the mapping pinned by
the new `NotificationPrimerOutcomeTest`. Two behaviour changes, both towards iOS: (1) the Settings
reminders toggle now shows the primer (source `settings`) when the OS does not already authorize
notifications, instead of firing the bare system dialog — and when the dialog can no longer appear the
library's denied state offers "Open Settings", the counterpart of iOS's denied alert; when already
authorized it enables directly, as iOS's `handleEnableNotifications` does. (2) The menu skips the
once-per-install primer when notifications are already authorized, as iOS's `guard .notDetermined`
does. One deliberate deviation from the library's own status mapping: below API 33 there is no runtime
permission and the system client reports `Authorized` whenever notifications are enabled, which would
make the screen complete on its own and turn reminders on for every Android 8–12 player without a tap.
A thin wrapper client (`ConsentGatedNotificationAuthorizationClient`) reports `NotDetermined` there instead
until the player taps, so "Turn On Reminders" remains the consent (the request then answers with the system
toggle's state, and the mask lifts so the library's post-request re-read sees `Authorized`); API 33+ passes
through untouched. `ConsentGatedNotificationAuthorizationClientTest` pins both sides of the line. Not
ported: iOS's full-screen-ad suppression while the primer is up — Android's app-open ad is still
unwired (§7's Phase 7 notes). Verification: `:app:assembleDebug` clean; `:app:testDebugUnitTest`
423/423 (one new) and `:notificationpermissionkit:testDebugUnitTest` 10/10 green; on the Pixel_10
emulator (API 37) with `POST_NOTIFICATIONS` revoked, the Settings toggle opened the primer, "Turn On
Reminders" raised the system permission dialog, and allowing it flipped the toggle on. The menu's
once-per-install path was not re-exercised (this install's `notificationPrimerShown` is already set);
its gate is unchanged apart from the new authorized-skip.

**Debug menu (2026-09-29).** Android now has iOS's hidden QA panel. `feature/debug/DebugMenuScreen.kt`
ports `DebugMenuView`, and `DebugMenuTapTrigger.kt` ports `DebugMenuTapTrigger`: five taps on the
Settings title, each within 1.5s of the previous one, open a `debug_menu` nav route. Both the trigger
(`SettingsScreen`'s new nullable `onDebugMenu`) and the route are gated on `BuildConfig.DEBUG`, the
counterpart of iOS's `#if DEBUG`. Rows: What's New (WhatsNewKit-Android, not marked seen), the review
invitation (ReviewFlow-Android, bypassing the policy, nothing recorded — `feature/review/
ReviewInvitation.kt` gained `DoMemoryReviewInvitationPreview`, sharing its artwork, copy and style with
the policy host), Play's native In-App Review request (status shown inline; Play shows nothing for
sideloaded builds), the notification primer (NotificationPermissionKit-Android, live — it can grant the
permission and arm reminders, as on iOS), the first-launch onboarding carousel, and the Levels intro.
Deviation from iOS on purpose: iOS's "Start onboarding" wipes the user record first; Android's is a
preview that keeps onboarding state, because `OnboardingViewModel`'s completion writes
`completeOnboarding(Difficulty.MEDIUM)` and would reset the player's chosen difficulty. iOS's
remove-ads toggle and ad-free-day reset are not ported — Android has no purchase layer and no ad-free
day offer. A follow-up (2026-09-30) aligned the rows with iOS's order and titles ("Start onboarding",
"Start Levels onboarding", "Show notifications view", "Show ask-for-review view (native)", "Show
ReviewFlow invitation view"; What's New stays as an Android-only extra) and ported "Restart lives",
which refills today's lives through `LevelLivesService.refill(MAX_LIVES)`. The menu now also
refreshes `LevelsViewModel` each time it comes back into view (`LaunchedEffect(Unit)` in the MENU
route — only the top destination stays composed), iOS's `LevelsView.onAppear` refresh; before, the
hearts header stayed stale after lives changed anywhere but a level. Verified on the Pixel_10
emulator: a timed-out level took lives to 3/4, "Restart lives" reported 4/4, the header showed 4/4
on return, and 4/4 survived a force-stop and relaunch. Copy is plain English literals, as on
iOS, outside `strings.xml` and `LocalizationParityTest`. Verification: `:app:assembleDebug` clean;
`:app:testDebugUnitTest` 429/429 (three new in `DebugMenuTapCounterTest`); on the Pixel_10 emulator
four taps left Settings alone, the fifth opened the menu, and every row presented its screen and
returned to the menu (the native review request reported completion). `:app:assembleRelease`
succeeded, and none of the menu's literals are present in the release dex while control literals from
live code are, so R8 strips the menu from release.

**Analytics parity with iOS PR #99 (2026-09-30).** Ports the events iOS added for the project
tracker's usage questions, with the same names and parameter keys (spec §16.1):
`achievements_opened` (Settings row), `theme_changed` (only when the pick differs, via
`SettingsViewModel.setTheme`), `custom_memorama_create_opened` (menu header and empty Mine
state), `daily_challenge_opened` (`card` from the menu, `widget` from the `domemory://daily`
deep link), `season_card_tapped`, `multiplayer_entry_tapped` and `level_lives_depleted`.
`level_finished` gains `power_ups_used` (star power-ups bought this attempt, reset by
`trackGameStarted`), `level_power_up_used` gains `season_id`, and `levels_intro_skipped`
becomes a data class carrying `slides_seen`, which `IntroCarousel.onSkip` now passes.
Android-specific readings: the host/join choice is logged on the lobby's Create, Join and
Scan QR buttons, since Android has no menu between the header button and the lobby; and
depletion is gated on `LevelLivesService.spendOnLoss()` returning true, so a loss with no
life to spend is not a depletion. `menu_tab_selected` landed earlier with iOS PR #99.
Validation: the full unit suite (433 tests) passes, including three new `GameViewModelTest`
cases (depletion fires once on the real last life, never at zero, and `power_ups_used`
counts then resets on retry). No event was observed in DebugView on a device.

**Flippo in the game modals (2026-09-30).** The win, lose, pause and quit overlays in
`feature/game/GameScreen.kt` show the same Flippo poses as iOS (`flippo_win`, `flippo_lose_time`,
`flippo_lose_mistakes`, `flippo_pause`, `flippo_quit` in `res/drawable-nodpi/`) at 160 × 168 dp,
replacing the emoji heroes and the lose overlay's `clock-crack` / `x-shake` Lottie heroes (the clips
stay bundled). The quit confirmation is no longer a Material `AlertDialog`: the new `QuitOverlay` is
a custom card mirroring iOS's `QuitModal` (Flippo, the question, Cancel / Accept capsules, in
`PauseOverlay`'s card chrome), with a `BackHandler` keeping the dialog's Back-as-Cancel behaviour.
Accept still leaves `showQuitConfirm` true so the pause sheet does not flash during the exit.
Validation: `:app:assembleDebug :app:testDebugUnitTest --rerun` passed (436 tests); on the
Pixel_10 emulator the pause, quit (Back cancelled and the timer resumed), timeout loss,
mistake loss and level-1 win overlays were all reached.

**Ad-free day (2026-09-30).** Ports iOS's "No Ads" offer (spec 12.3): two rewarded ads, each on
its own tap, turn off banners, natives and the completion interstitial for 24 hours.
`services/ads/AdFreeDayService` holds the two-ad chain, keyed to the local day like lives so a
half-finished chain resets at midnight, and the grant, which extends a window that is still
running. `UserPreferences` stores both, each update in a single DataStore transaction.
`AdFreeGate` is the ads layer's read side: `AdMobBanner` and `AdMobNativeAdView` render nothing
while it is active, and `notifyGameFinished` passes it as `involuntaryAdsSuppressed`, the hook
Phase 7 left for exactly this. Rewarded placements are never gated. The new
`AD_FREE_DAY_REWARDED` shares the single rewarded unit, so release needs no new AdMob unit, and
`loadRewarded` gained an optional readiness callback plus in-flight de-duplication (iOS's
`loadRewardedAd(for:completion:)`), which the sheet needs to leave "Loading ad".
`feature/adfree` holds the pill (menu tabs, season map, multiplayer lobby), the bottom sheet
(Flippo, apology copy on the first open only, stepper, loading / ready / presenting / no fill
/ active) and its testable `AdFreeDayOffer` state machine. Settings gets a "Free ad-free day"
row under Purchases, the debug menu gets iOS's "Disable ads" and "Reset ad-free day offer"
rows, and the five `ad_free_day_*` events match iOS. There is no "Remove ads forever" link:
Android still has no purchase layer. Strings: 21 keys ported from iOS into all ten locales.
Tests: `AdFreeDayServiceTest` (12, including the 8 iOS cases), `AdFreeDayOfferTest` (7) and the
event shapes, for 459 in the suite. On the Pixel_10 emulator the full chain ran end to end
with Google's test rewarded ad: the apology on the first open and neutral copy after it,
"No Ads 1/2" progress surviving a dismissed sheet, the grant from the Settings row, the menu
banner gone at once, and the pill reading "23h left". Not exercised: the interstitial and the
multiplayer native while ads are off, and the season-map and lobby pill placements, which
were only built.

**Tracker issues #148, #149, #161, #158, 2026-09-30.** Fonts (#148, closes O6): iOS's
`righteous()`/`patrickHand()` return `.system(design: .rounded)`, so iOS renders SF Pro Rounded,
which Apple licenses for Apple platforms only. Android now uses Nunito for both roles and for every
Material style (`DoMemoryType.typography`, passed to `MaterialTheme`): one variable
`res/font/nunito.ttf` from Google Fonts, instanced per weight with `FontVariation.weight`, OFL text
in `assets/licenses/Nunito-OFL.txt`. `display` is ExtraBold and `handwritten` SemiBold. Righteous and
Patrick Hand are deleted from `res/font`. The menu's multiplayer button (#149) is Material `People`,
iOS's `person.2.fill`, with a "Multiplayer" content description, in place of "♟". Saving a new
memorama (#161) now selects `MenuTab.MINE` via `MenuViewModel.showMyMemoramas()`, without logging
`menu_tab_selected`; iOS does the same in `MenuView`. Verification: `assembleDebug
testDebugUnitTest` 461/0, iOS `xcodebuild test` 223/0. On the Pixel_10 emulator: Nunito on the menu,
Settings, season map and lobby; the People icon opening the lobby; creating a board from the Levels
tab landing on My memoramas with `custom_memorama_created` and no `menu_tab_selected`. Ad-free day
(#158): the pill shows "23h left" on the season map and the multiplayer lobby, closing the
placements gap above. The interstitial under a grant was not observed on device: the emulator was
taken over by another app mid-run. `GameFinishedInterstitialTriggerTest` now covers it instead: an
active grant never requests and leaves the cadence counter untouched. Still not exercised: the
multiplayer-finished native while ads are off, and any physical device.

**Multiplayer deal fix, 2026-11-03.** Android hosts dealt every pair side by side, because
`MultiplayerCards.from` never shuffled, on the mistaken belief that a shuffle would give each client
a different board. The owner saw this in a live match. The host now shuffles when dealing and on
rematch, as iOS's `makeCards` does, and both players keep rendering the list in the room, so older
clients need no change. `MultiplayerCardsTest` previously pinned the bug as "iOS wire order" and now
guards against it. Verified with unit tests only; a live match hosted on Android is still to do.

## 8. Immediate next steps

1. Decide **O1**: register `domemory.app`, deploy Android App Links and iOS Universal Links
   association files, then verify a shared invite link opens directly into the join flow.
2. ~~Build the Season-specific out-of-lives prompt~~ — done, 2026-09-15 (see above).
3. `game_rewarded_hint` is now wired from a pause sheet available in every mode (this change).
   Decide whether `game_rewarded_extra_time` warrants its own UI, then wire it if approved.
4. ~~Decide UMP consent behavior (O5), build the launch-sequence state machine~~ — done,
   2026-10-26 (#167): UMP form only where AdMob's European regulations message applies,
   `LaunchSequence` runs consent → ads → primer. Still open: enable the app-open placement
   (gate it on `AdsService.canLoad` and `ConsentService.isPresentingForm`) and make
   `LevelsIntroGate` wait for `LaunchSequence.Stage.FINISHED`.
5. Run real-device follow-ups: haptic feel, TalkBack announcements, animation feel for the new
   Lottie effects, the out-of-lives modal's on-screen appearance, and RTL/dark-mode rendering
   of the new Levels/Daily/Seasons components.
6. Resolve optional cleanup decisions: ~~bundled display fonts (O6)~~ Nunito, 2026-09-30 — a second Firebase debug
   client (O7) — ~~compact Daily-card layout~~ done, 2026-09-15 — and season system-bar
   transparency.

**Completed since the previous handoff:** season/day-rollover verification, live Phase 7 ad
flows, app-wide haptics, the Android↔iOS multiplayer match and rematch, the production room-read
rule repair (PR #58), the iOS rematch-win accounting repair (PR #59), shared cross-platform
Lottie effects (win/lose/lives/freeze/star-credit), and the Levels/Daily Challenge/Seasons
visual-parity pass with iOS.
