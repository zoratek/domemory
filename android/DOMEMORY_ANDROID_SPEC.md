# DoMemory — Android Port Specification

**Source of truth:** the shipping iOS app in this repository at `ios/`,
version **4.2.0** (bundle id `com.ezequielbrrt.domemory`, App Store id
`1533115091`). Both platforms share that bundle id and one Firebase project.

This document describes *what the app does* — every screen, rule, constant, data
contract and backend integration — in enough detail to build the Android app from
scratch without reading the Swift. Where a rule exists for a non-obvious reason,
the reason is written down, because those are the parts that get silently dropped
in a port and turn into bugs.

Nothing in here is aspirational, apart from §22, which is marked as planned. Every
other number, key and behaviour listed is what iOS 4.2.0 actually ships.

---

## 1. What the app is

DoMemory is a **memory card game** (memorama). You flip cards two at a time to
find matching pairs before a countdown expires. Around that core loop it stacks
six things that make it a live product rather than a toy:

1. **A catalog of curated boards** — ~134 emoji card sets served from Firebase
   Realtime Database, filtered by the player's chosen difficulty.
2. **Endless Levels** — an infinite, procedurally generated progression with
   stars, a daily lives budget, a mistake budget and a spendable star economy.
3. **Season Levels** — limited-time themed level runs (e.g. "Spooky Season"),
   published from Firebase without an app release, with their own emoji pool,
   artwork and countdown.
4. **Daily Challenge** — one deterministic board per calendar day, identical for
   every player worldwide, with a streak.
5. **Real-time multiplayer** — two-player turn-based matches over Firebase
   Realtime Database, joined by a 6-character code, QR scan or invite link.
6. **Custom memoramas** — player-authored emoji card sets stored locally.

Android monetization is currently AdMob (banner / interstitial / rewarded / app-open /
native). Remove Ads purchases and the two-ad rewarded ad-free day (§12.3) are deferred.

### Platform targets (iOS, for reference)

| Item | Value |
|------|-------|
| Min OS | iOS 18.6 |
| Devices | iPhone + iPad, portrait-only on iPhone; all orientations on iPad |
| Locales | `en`, `es-419`, `pt-BR`, `de`, `it`, `fr`, `hi`, `ja`, `ko`, `zh-Hans` |
| UI framework | SwiftUI, `@Observable` view models |
| Persistence | CoreData (one record), UserDefaults (everything else) |

**Recommended Android equivalents** (suggestions, not requirements — see §14):
Jetpack Compose, `ViewModel` + `StateFlow`, DataStore (Preferences) instead of
UserDefaults, Room only if you want it (CoreData holds a single row and DataStore
covers it), Firebase Android SDK, Google Mobile Ads Android SDK, Google Play
Billing Library instead of StoreKit 2.

---

## 2. Screen map and navigation

```
LaunchScreen (1.2s splash overlay, fades out)
      |
      +-- first launch, no saved settings --> Onboarding
      |         FeatureIntroView  (3-slide carousel, skippable)
      |         HomeView          (difficulty picker: Easy/Medium/Hard/Very hard)
      |             --> writes UserSettings, falls through to Menu
      |
      +-- returning user --------------------> MenuView
                |
                +-- What's New sheet (once per version upgrade)
                +-- Notification permission primer (once per install)
                +-- ATT prompt -> AdMob start -> app-open ad
                |
                +-- Header: [DoMemory]  [join multiplayer]  [create memorama]  [settings]
                +-- Cards row: Daily Challenge card  (+ Season card when a season is live)
                +-- "Random game" button
                +-- Home banner ad
                +-- Bottom tab bar (3 tabs, opens on Levels):
                       [Levels]  [My memoramas]  [All]
                              |          |          |
                              |          |          +-- grid of Firebase boards for current difficulty
                              |          +-- grid of locally created boards
                              +-- LevelMapView (endless) --> MemorizeView(level)
                |
                +-- Season card --> SeasonLevelsView --> MemorizeView(season level)
                +-- Daily card   --> MemorizeView(daily)
                +-- any board    --> MemorizeView(free)
                +-- Settings     --> Achievements
                +-- Multiplayer  --> host (empty room, pick game in lobby) or join --> live match
```

Deep links land on the Menu and are routed from there (see §11).

---

## 3. Core game model

### 3.1 Card and board

A board is a shuffled array of cards. Each card has:

| Field | Type | Meaning |
|-------|------|---------|
| `id` | Int | unique per card |
| `itemId` | Int | **pair key** — two cards match iff their `itemId` is equal |
| `content` | String | what is drawn on the face (an emoji, or a text/image token) |
| `isFaceUp` | Bool | |
| `isMatched` | Bool | |
| `bonusTimeLimit` | 2.0 s | per-card "answer quickly" window, drives the pie indicator |
| `lastFaceUpDate`, `pastFaceUpTime` | timing state for the pie | |

There are **two board constructors**, selected by the board's `isDoubleItem` flag:

- **`isDoubleItem == true`** (all emoji boards, all generated boards): each item
  in `items` produces **two** cards sharing that item's index as `itemId`.
  `N` items → `2N` cards → `N` pairs.
- **`isDoubleItem == false`**: each item produces **one** card, and items are
  paired by *adjacency* — items 0&1 match, 2&3 match, and so on. Concretely:
  `itemId = pairIndex` when `pairIndex` is even, else `pairIndex - 1`.
  `N` items → `N` cards → `N/2` pairs. This exists for boards where the two faces
  of a pair are different content (e.g. a word and a picture). No board in the
  current catalog uses it, but the model and multiplayer both support it — keep it.

After construction the card array is **shuffled**. Shuffling happens per play,
even for deterministic boards (see §6.1) — the *content* is deterministic, the
*layout* never is, so a shared screenshot can't be used to memorize positions.

### 3.2 Matching rules (`choose(card:)`)

Tapping a card is ignored when the card is already face-up or already matched.
Otherwise:

- If **no** unmatched card is currently face up: turn this one up. (Implementation
  detail: this also flips every other unmatched card down, so at most one
  "pending" card exists.)
- If **exactly one** unmatched card is face up:
  - same `itemId` → mark **both** matched, leave both face up.
  - different `itemId` → increment `failedTries`, leave both face up.

`failedTries` is the app's error counter and feeds star ratings, the mistake
budget, the win screen and analytics.

### 3.3 Post-tap timers

| Timer | Delay | Effect |
|-------|-------|--------|
| Flip-back | 2.0 s | when two unmatched cards are face up, both flip down (animated, 0.5 s ease-in-out) |
| Matched hide | 1.0 s | matched face-up cards fade off the board (0.35 s ease-in-out), then win check runs |
| Mistake loss | 0.8 s | when the mistake budget is exhausted, the loss is deferred this long so the player sees the pair that finished them |

The flip-back timer is **cancelled on the next tap** — a mismatched pair stays
tappable during those 2 seconds, and tapping a third card immediately resolves the
board rather than waiting.

**Win condition:** every card `isMatched`. Checked after the matched-hide timer
and on every tap. The win must fire **once** on the transition (guard against
re-firing, otherwise stats and analytics double-count).

### 3.4 The pie indicator

Each card can show a shrinking pie wedge representing `bonusTimeRemaining /
bonusTimeLimit` (2 s). It is a pure "you're taking too long on this card" visual,
worth no points. It is shown only when:

- **Levels / Seasons:** level number `>= 25`.
- **Everything else (free play and Daily Challenge):** the **player's own
  difficulty setting** is `hard` or `veryHard` — see the warning in §4 about
  *which* difficulty this reads.

### 3.5 Board layout

The grid is square-ish: `columns = ceil(sqrt(cardCount))`,
`rows = ceil(cardCount / columns)`. Cards are sized to fill the available area
with 10 pt spacing and 16 pt padding, so a 6-card board shows large cards and a
24-card board shows small ones. There is no scrolling — the whole board is always
on screen.

### 3.6 Quitting mid-game

A close ("×") button sits in the HUD, top-left, for every mode (free play, Daily
Challenge, Levels, Seasons). Tapping it pauses the game and shows a confirmation
dialog (`game_quit_confirmation`, buttons `common_cancel`/`common_accept`) —
there is no single-tap way to leave an in-progress game. Cancel resumes the
game exactly where it left off; confirm abandons it.

Abandoning mid-game is a pure quit, not a loss: no stats, lifetime stars, or
Levels/Seasons life are touched, and no win/loss is recorded — quitting must
never cost more than a genuine loss would (mirrors iOS's `tapOnExit()`, which
deliberately never calls `logGameFinishedIfNeeded`). This is distinct from the
Levels/Seasons lose screen's own "Menu" button, which commits that loss (a life
already spent) before leaving — the two must not share one code path, or a
mid-game quit would silently spend a life. `quit_confirmed` (§16.1) fires on
confirm once an analytics pipeline exists on Android (currently absent — see
the "Deliberately deferred" list in `ANDROID_PLAN.md` §7); until then this is
UI-only parity.

A navigation fires once per screen. A screen that is leaving is still drawn,
and still takes taps, for its whole exit transition, so a second tap on Accept,
Menu, Next level or a back button would navigate again: on Android, a
double-tapped Accept popped the Menu too and left a blank screen. Android drops
any navigation from a screen that is no longer resumed (`rememberResumedGuard`
in `NavGraph.kt`), and Skip refuses a second purchase for the same loss.

### 3.7 Leaving the app mid-game

When the app leaves the foreground during a game that is still in play (no
outcome yet, not already paused), the game pauses exactly as the pause button
would, and the pause sheet is waiting on return. It pauses silently: no haptic
and no `pause_opened`, since the player tapped nothing. Only the player's own
Continue resumes it. A finished game is left alone.

This is Android-only. Android keeps the main thread, and with it the countdown,
running while the app is in the background, so without it a player who switches
apps returns to an out-of-time loss. iOS suspends the app instead, which stops
its tick loop.

---

## 4. Difficulty

Four levels, stored as a lowercase string.

| Difficulty | id | Time limit | Interstitial every N wins | Pie |
|---|---|---|---|---|
| `easy` | 0 | 110 s | 3 | no |
| `medium` | 1 | 60 s | 3 | no |
| `hard` | 2 | 60 s | 2 | yes |
| `veryHard` | 3 | 70 s | 2 | yes |

Note that `medium` and `hard` share a time limit — difficulty is expressed
through board size (from the catalog) rather than the clock alone. `veryHard`
getting *more* time than `hard` is deliberate: its boards are larger.

> **Two different "current difficulty" values exist, and they are not
> interchangeable.** Getting this wrong changes how long every game lasts.
>
> - **The player's setting** (from stored `UserSettings`) drives the **time
>   limit** and the **pie indicator** — in free play *and* in the Daily
>   Challenge.
> - **The board's own `difficulty`** (falling back to the player's setting when
>   the board carries none, or an unparseable one) drives the **analytics
>   dimension**, the **interstitial frequency**, the **difficulty label shown on
>   the win screen**, and **lifetime stat recording**.
>
> So a Daily Challenge board declares `medium`, but a player set to `easy` gets
> 110 seconds on it and no pie, while its analytics still report `medium`.
> Levels and Seasons bypass both: their clock comes from `LevelCurve` and their
> pie from the level number.

The player's chosen difficulty:

- filters the **All** tab (only boards whose `difficulty` matches are shown),
- sets the clock and the pie for every non-level game,
- is the fallback for any board that carries no parseable difficulty of its own,
- is chosen during onboarding and changeable in Settings,
- is the **only** thing stored in CoreData (`UserSettings.dificulty` — note the
  original misspelling; it is a persisted attribute name, keep it or migrate
  deliberately). `UserSettings.points` also exists and is read into the menu but
  is effectively unused dead state; do not port it.

Changing difficulty in Settings triggers a full menu reload on dismiss (the
catalog is re-fetched and re-filtered) — but only if the value actually changed.

---

## 5. Game modes

The gameplay screen (`MemorizeView` / `MemorizeViewModel`) serves **all** modes.
A `GameMode` value decides which extra rules apply:

```
GameMode = free | dailyChallenge | level(LevelContext)

LevelContext = {
  number:      Int          // level as the player sees it, 1-based
  store:       LevelProgressStore   // who owns unlocks/stars/boards
  seasonID:    String?      // nil = endless Levels
  levelCount:  Int?         // nil = endless; a season's length otherwise
}
```

`LevelProgressStore` is the seam that lets endless Levels and Seasons share one
gameplay screen. It must expose:

```
highestUnlockedLevel: Int
stars(for level: Int): Int
isUnlocked(level: Int): Bool
board(for level: Int): Board
recordCompletion(level, didWin, timeRemaining, totalTime, failedTries): Int  // returns stars
skipLevel(level: Int)
nextLevel(after level: Int): Int?     // endless: always level+1; season: nil past levelCount
```

Two implementations: `LevelProgressService` (endless) and
`SeasonLevelProgressStore` (a season's progress service bound to that season's
emoji pool and length).

**Port this abstraction.** It is what keeps Seasons from being a copy-paste of
Levels, and it is the single place the "a season has a last level" ceiling is
enforced — the win screen must not offer level 21 of a 20-level season.

### Feature availability per mode

| Feature | Free | Daily | Levels | Season |
|---|---|---|---|---|
| Countdown | player's difficulty | player's difficulty | level curve | level curve |
| Mistake budget | no | no | yes | yes |
| Power-up bar | no | no | yes | yes |
| Stars earned | no | no | yes | yes |
| Daily lives spent on loss | no | no | yes | yes |
| Rewarded extra time / hint | yes | yes | yes | yes |
| Next-level button on win | no | no | yes | yes (except last level) |
| Streak | no | yes | no | no |
| Share result card | yes | yes | yes | yes |
| Per-board played/won stats | yes | yes | yes | yes |

---

## 6. Deterministic board generation

Three features generate boards locally instead of downloading them. All three use
the same RNG so any device produces the same board for the same seed.

### 6.1 The seeded RNG

**SplitMix64**, seeded by an **FNV-1a 64-bit hash** of a seed string.

```
init(seed: String):
    hash = 14695981039346656037            // FNV offset basis
    for each UTF-8 byte b of seed:
        hash ^= b
        hash = hash * 1099511628211        // FNV prime, wrapping
    state = hash

next() -> UInt64:
    state = state + 0x9E3779B97F4A7C15                       // wrapping
    z = state
    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9                 // wrapping
    z = (z ^ (z >> 27)) * 0x94D049BB133111EB                 // wrapping
    return z ^ (z >> 31)
```

It is used through a **seeded shuffle** of the emoji pool, then `prefix(pairCount)`.

> **Correction (2026-11-03).** The basis above is the standard one, and it is what
> Android uses. iOS actually ships `1_469_598_103_934_665_603`, which is one digit
> short (`SeededGenerator.swift:18`), so the two platforms produce different streams
> for the same seed, whatever the shuffle does. Live iOS boards depend on that value.

> **Critical for cross-platform parity.** The Daily Challenge is advertised as
> "the same board for everyone". If Android's shuffle differs from Swift's
> `shuffle(using:)`, Android players get a different board than iOS players on the
> same day. Swift's `shuffle(using:)` is a **Fisher–Yates from the end**:
> for `i` from `count-1` down to `1`, pick `j = random in 0...i` and swap
> `elements[i]` and `elements[j]`. Swift draws that random value from the
> generator using its `random(in:)` implementation. **Verify parity empirically**
> before shipping: generate the boards for a fixed set of seeds on both platforms
> and diff them. If exact parity proves impractical, decide explicitly whether
> Daily Challenge parity is a requirement or whether Android can have its own
> per-day board — but make that a decision, not an accident.

### 6.2 The emoji pool

A fixed, curated, order-stable list of 48 visually distinct emoji. **Order is part
of the contract** — seeded selection depends on it. Only ever append, never
reorder or remove.

```
😀 😎 🥳 😍 🤓 😴 🤖 👻 💩 🐶
🐱 🦊 🐻 🐼 🐸 🐵 🦁 🐯 🦄 🐝
🐢 🐙 🦋 🌵 🌸 🍄 🍎 🍌 🍉 🍓
🍕 🍔 🌮 🍦 🎈 ⚽️ 🚀 ⭐️ 🌈 🔥
💎 🎸 🎲 🎯 👑 🎁 ❤️ ⚡️
```

### 6.3 The three generators

| Feature | Seed string | Pool | Pair count |
|---|---|---|---|
| Daily Challenge | `"YYYYMMDD"` (local calendar) | `EmojiPool.all` | **6**, fixed |
| Endless Levels | `"level-{n}"` | `EmojiPool.all` | `LevelCurve.pairs(n)` |
| Season Levels | `"season-{seasonId}-{n}"` | the season's `emojiPool` | `LevelCurve.pairs(n)` |

All three produce a board with `isDoubleItem = true`, `difficulty = "medium"`,
`itemType = "string"`.

---

## 7. Endless Levels

The default landing tab. An infinite ladder of procedurally generated boards.

### 7.1 The difficulty curve

Table-driven with **linear interpolation between anchors**, and the last anchor's
value is held constant forever after. Deliberately not a formula — the curve is
sub-linear and this keeps it retunable.

```
pairs(level):     anchors (1,3) (5,4) (10,6) (25,9) (50,12)      // caps at 12
seconds(level):   anchors (1,90) (5,85) (10,75) (25,60) (50,45) (80,35)   // floors at 35
maxFailures(level): anchors (1,4) (5,6) (10,8) (25,11) (50,14)   // caps at 14

interpolate(level, anchors):
    L = max(1, level)
    if L <= first.level:  return first.value
    if L >= last.level:   return last.value
    find the anchor pair (lo, hi) with L <= hi.level
    t = (L - lo.level) / (hi.level - lo.level)
    return round(lo.value + t * (hi.value - lo.value))
```

`maxFailures` deliberately tracks roughly `pairs + 2`. Even perfect recall costs
N/2–N mismatches on an N-pair board, so a budget at or below the pair count would
make levels unwinnable.

The **12-pair cap matters beyond gameplay**: it is the minimum size of a season's
emoji pool (§9.2).

### 7.2 Stars

Awarded on a **win only**, from time left and mistakes made:

```
fraction = timeRemaining / totalTime
3 stars  if fraction >= 0.50 AND failedTries <= 1
2 stars  if fraction >= 0.25
1 star   otherwise
```

Rules:

- A level's stored rating is a **high-water mark** — it can be raised by a replay,
  never lowered.
- **Only the improvement is credited** to the spendable wallet. Replaying a
  3-star level pays nothing; beating your own 2-star run with 3 stars pays 1.
  This is the anti-farming rule — without it the star economy is free money.
- Clearing level `n` sets `highestUnlockedLevel = max(current, n+1)`.

### 7.3 Two star counters — keep them separate

| Counter | Key | Meaning |
|---|---|---|
| Lifetime stars | `levels.lifetimeStars` | **Monotonic mastery score.** Spending never lowers it. Displayed in the Levels header. Stored (not summed) so reading it is O(1) as the player climbs. |
| Wallet balance | `levels.wallet.balance` | **Spendable currency.** Credited by wins, debited by purchases. |

Season play credits the **wallet** but deliberately does **not** touch
`levels.lifetimeStars` — that value is the endless-Levels mastery score and season
play must not inflate it.

**Migration (iOS-only concern, but understand it):** installs predating the star
economy backfill `lifetimeStars` once by summing per-level ratings, and seed the
wallet with that same total (they had never spent anything). Android has no such
legacy — skip it.

### 7.4 Daily lives

- **4 lives per day**, shared globally across endless Levels *and* every season.
- Reset lazily: the first read on a new local calendar day resets to 4. Uses the
  same `YYYYMMDD` day key as the Daily Challenge, so both roll over together at
  the player's local midnight.
- A life is spent **only on a loss** (timeout or mistake bust). Quitting costs
  nothing. Winning costs nothing.
- At 0 lives, tapping any level tile is **refused** — a warning haptic fires and
  the Out-of-Lives modal appears instead of starting a game.
- Refills: **rewarded ad** (+1) or **10 stars** (+1). Both cap at 4.

### 7.5 The mistake budget

Levels and Seasons only. Busting `maxFailures(level)` ends the run 0.8 s later,
with `loseReason = tooManyMistakes`.

- The HUD shows `used/max` and turns warning-coloured when **2 or fewer** mistakes
  remain.
- If the clock hits zero during that 0.8 s window, **whichever failure landed
  first wins** — never overwrite an existing lose reason. A timeout must not be
  offered the mistake rescue.
- Pausing during the delay must not let the player play on past the budget: the
  loss is re-armed when the timer restarts.

**The rescue:** a rewarded ad or **8 stars** forgives **3 mistakes** and resumes
the *same* board — matched pairs stay matched. It does **not** count as a game
finish: no life is consumed, no loss is recorded, no interstitial. The clock is
floored at **15 seconds** after a rescue, otherwise the rescue is worthless when
the budget runs out late (at 0 s the countdown can't restart at all).

### 7.6 Power-ups

Bought with stars mid-game, in the bar under the HUD. **No confirmation step** —
costs are small and the clock is running, so a modal costs more than a misfire.
Levels and Seasons only.

| Power-up | Cost | Effect | Icon |
|---|---|---|---|
| Extra time | 3★ | `timeRemaining += 15` | `goforward.15` |
| Peek | 4★ | flips **every unmatched card** face up for **1.5 s** | `eye.fill` |
| Freeze | 5★ | holds the countdown for **10 s** | `snowflake` |
| Reveal pair | 6★ | turns up one unmatched matching pair (and flips everything else down) | `wand.and.stars` |

Ordered as a power ladder — the more it does, the more it costs. An average clear
pays ~2 stars.

Implementation notes that matter:

- **Freeze** is implemented as a `frozenUntil` deadline that the tick loop checks,
  *not* by cancelling the timer. Cancelling would tear down the card flip-back
  scheduling. The HUD needs a separate observable `isFrozen` flag, because nothing
  else changes while frozen (the displayed number stops moving) and the view would
  otherwise have no signal to re-render. The timer chip turns frosty blue while
  frozen, and a `select` haptic fires when the clock restarts (easy to miss
  visually).
- **Peek** must be ended if the game is paused, otherwise pausing mid-peek
  cancels the scheduled flip-back and leaves the board revealed for free.
- **Pausing holds Freeze.** The deadline is wall-clock, so the time left on it is
  saved when the clock stops and a fresh deadline is set from it on resume.
  Otherwise a pause during Freeze burns the Freeze the player paid for. A loss
  holds it the same way, so a forgive-mistakes rescue (§7.7), which resumes the
  same board, gets back the Freeze that was running when the loss landed.
- **Peek and Freeze can't be bought while they run.** A second one restarts the
  effect rather than extending it, so it would charge twice for what plays as
  one. Their buttons are disabled until the effect ends (`isPeeking`, `isFrozen`),
  and the view model refuses the purchase before spending. A Freeze held by a
  pause still counts as running.
- **One purchase at a time.** On Android the star spend is a suspending DataStore
  write, so a purchase still in flight refuses a second tap. A double tap buys
  once.
- **Reveal pair** re-arms the normal 2 s flip-back.

### 7.7 Buying past a wall

From the lose screen:

| Action | Cost | Effect |
|---|---|---|
| Buy a life | 10★ | +1 life (capped at 4), restarts the level |
| Forgive 3 mistakes | 8★ or rewarded ad | resumes the same board, +15 s floor |
| Watch ad for +1 life | rewarded ad | +1 life, restarts the level |
| Watch ad for +30 s | rewarded ad | `timeRemaining += 30`, clears the loss, resumes |
| Skip this level | 15★ | **confirmation dialog required**; only offered when a life is left after it |

**Layout:** the lives row carries the spendable star balance on its right. The
screen offers **one rescue**, chosen by why the game ended — a life when out of
lives, forgiven mistakes when the budget ran out, 30 s when the clock did — as a
title ("Forgive 3 mistakes") over its payments side by side: a filled ad button and
an outlined star price. A payment that isn't available (no ad filled, not enough
stars) is left out; a rescue with neither isn't shown. Try again follows, then Skip
and Menu as text buttons. Menu is an outlined button only when nothing else is on
the card.

**The life at stake:** a Level loss is only booked when the player leaves it (Try
again, Menu, Skip). While the lose screen is up, the heart it would cost is still
full, so it **pulses** rather than breaking, and the rescue carries "Continue now and
you won't lose a life." The heart-break effect plays only when a life is actually
spent in place (Try again on the last life, which leaves the screen in its
out-of-lives state).

**Skip availability:** skipping books the loss, so it is offered only when the
player would still have a life afterwards — never when out of lives, nor when the
skip would spend the last one. Otherwise the map's lives gate refuses the level the
player just paid to unlock.

**Skip semantics:** unlocks the next level, stores **no stars** (renders as
cleared-with-0-stars, replayable for credit later), records the attempt as a
**loss** (skipping buys the unlock, not a clean record), suppresses the completion
interstitial (charging 15★ and then serving an ad is the worst moment in the app
for one), and returns to the map rather than auto-starting the next level — so the
lives gate there still decides whether they can play on.

### 7.8 The level map

Shared by endless Levels and Seasons; the two differ only in header, tile source
and background.

- 4-column grid of numbered tiles, 18 pt column spacing / 22 pt row spacing.
- Three tile states: **cleared** (shows 1–3 stars, replayable), **current**
  (highlighted, animated), **locked** (not tappable — enforced in the map, not in
  each caller).
- The **current tile pulses**: an expanding ring plus a subtle breathing scale.
  Only the current tile animates; locked and cleared tiles pay nothing for it.
- Every tile **presses down to 0.92 scale and springs back** on tap
  (`spring(response: 0.25, dampingFraction: 0.6)`).
- **Endless paging:** render `highestUnlockedLevel + 20` tiles; when a tile within
  4 of the end scrolls into view, append another 20. The map grows forever.
- **Seasons:** render exactly `levelCount` tiles, once. No paging, no locked tile
  past the season's last level.
- The background (a season's artwork) is **fixed** while tiles scroll over it, and
  extends under the safe areas so nothing bands at the top or bottom.

### 7.9 The Levels intro

A 4-slide carousel (Endless Levels / Earn Stars / Lives Refill Daily / Mind Your
Mistakes), shown **once per install** and reopenable from an info button in the
map header.

Timing rule worth copying: Levels is the landing tab, so the intro **waits for the
launch sequence to finish** — the tracking prompt, the What's New sheet and the
notification primer must all be done first, or the covers race each other. The
"seen" flag is set **on dismiss**, not on present, so a kill mid-intro leaves the
player eligible to see it again.

---

## 8. Daily Challenge

- **One board per calendar day**, 6 pairs, medium difficulty, identical content
  for every player worldwide (seeded by `YYYYMMDD` in the *local* calendar).
- **One attempt per day.** Any finish — win *or* loss — consumes the day and locks
  the card. Recording is idempotent within a day.
- **Streak:** a win on a day consecutive with the last winning day increments;
  otherwise it resets to 1. A loss sets the streak to **0**.
- `longestStreak` is tracked separately and feeds Achievements.
- Milestone analytics fire at streaks of **3, 7, 14, 30, 100**.
- Finishing refreshes the streak-at-risk reminder (§11.2) and the home-screen
  widget.

**Day-boundary helper** (shared with lives, seasons and the widget):
`dayKey(date) = format("%04d%02d%02d", year, month, day)` in `Calendar.current`.
Everything that needs "what day is it" goes through this one function so nothing
can disagree about midnight.

### 8.1 Home-screen widget

A small widget showing the current streak (`🔥 N`), the title, and whether today's
challenge is done. Tapping it deep-links into today's board.

- Reads state from an **App Group**-shared preferences store
  (`group.com.ezequielbrrt.domemory`), falling back to the app's own store if the
  App Group is unavailable — the app must still work either way.
- Timeline refreshes at the **next local midnight**, so the "completed" lock
  clears for the new day.
- The app force-refreshes the widget after every daily completion.

**Android:** this maps to a Glance `AppWidget` reading a shared DataStore. No App
Group concept is needed — same process, same storage. Keep the midnight refresh
(use `WorkManager` or a widget update at midnight).

---

## 9. Season Levels

A limited-time themed level run, **published from Firebase without an app
release**. This is the app's live-ops lever: a season is put live, extended or
killed by editing a database node.

### 9.1 Where it appears

- While a season is active, the menu shows a **Season card** sharing a row with
  the Daily Challenge card (which shrinks to a compact layout). With no active
  season the Daily card keeps its full-width layout.
- Tapping it opens **SeasonLevelsView**: the shared level map under a season
  header showing the season's icon, title, a `cleared / total` progress bar, the
  star total and a days-left countdown.
- The progress bar's fill **eases to its new width with a spring** rather than
  snapping when a level is cleared.
- Once every level is cleared, the header shows a **completion state** ("Season
  complete! — You cleared every level. Replay any of them to improve its stars.")
  so a finished season lands somewhere instead of ending on a wall of tiles.
- The nav bar is **transparent when the season carries artwork** so the image
  reaches the top of the screen; opaque otherwise.

### 9.2 The `/seasons` payload

`/seasons` is a **dictionary keyed by season id** (unlike `/data`, which is an
array), so `id` does not appear in the value body — inject the key as `id` before
decoding.

```jsonc
{
  "spooky-2026": {
    "enabled": true,                    // KILL SWITCH; absent => false
    "startDate": "2026-09-01",          // inclusive, YYYY-MM-DD
    "endDate": "2026-11-02",            // inclusive
    "priority": 10,                     // highest wins when several are active
    "levelCount": 30,                   // >= 1, required
    "icon": "🎃",                       // optional, falls back to "✨"
    "accentColor": "#FF6B1A",           // optional #RRGGBB, falls back to brand primary
    "backgroundImageURL":     "https://.../background-light.png",  // optional
    "backgroundImageURLDark": "https://.../background-dark.png",   // optional
    "cardImageURL":           "https://.../card.png",              // optional
    "emojiPool": ["👻","🎃","🕷️","🦇","🧛","⚰️","🕸️","🔮","🍬","🧟","🪦","😱"],
    "strings": {
      "en":      { "title": "Spooky Season", "subtitle": "30 haunted levels" },
      "es":      { "title": "Temporada de Sustos", "subtitle": "30 niveles embrujados" },
      "zh-Hans": { ... }, "zh-CN": { ... }, "pt-BR": { ... }, ...
    }
  }
}
```

### 9.3 Validation — fail closed on structure, fall back on decoration

Rules applied at decode time. **A season that fails validation is skipped, but one
bad season must never cost the player a second, valid one.**

| Field | Rule |
|---|---|
| `enabled` | absent ⇒ `false`. A season appears only when the database says so explicitly. |
| `levelCount` | absent or `< 1` ⇒ **reject the season**. |
| `emojiPool` | Deduplicate (preserving order — the seeded shuffle depends on it) and drop empties. Fewer than **12 distinct** entries ⇒ **reject**. |
| `startDate` / `endDate` | Must be strict `YYYY-MM-DD`. Unparseable ⇒ the season is never active. |
| `priority` | absent ⇒ `0`. |
| `icon` | absent/blank ⇒ `✨`. |
| `accentColor` | not a 6-digit hex (with or without `#`) ⇒ brand primary. 8-digit form is **not** supported. |
| artwork URLs | must be absolute **`https`** with a non-empty host. Blank or malformed ⇒ `null`, and the surface falls back to flat colour. |
| `strings` | absent ⇒ `{}`; a missing `subtitle` ⇒ `""`. |

**Why 12:** `LevelCurve.pairs` tops out at 12 pairs and holds that forever, so a
season with fewer than 12 distinct emoji cannot fill its own level-25+ boards.
Derive the constant from the curve so retuning the curve moves the floor.

**Why `https` specifically:** App Transport Security blocks cleartext `http` on
iOS, so an `http` URL would fail at load with nothing on screen to explain why.
Android has an equivalent (cleartext blocked by default since API 28) — keep the
same rule so a season authored for one platform behaves on both.

### 9.4 Activation window

```
isActive(date) =
    enabled
    AND dayKey(startDate) <= dayKey(date) <= dayKey(endDate)
```

Compared on the zero-padded `YYYYMMDD` **string**, not on parsed dates: string
ordering on that format is chronological, bounds are inclusive by construction,
and no timezone offset can shift a boundary day by one. Evaluated in the player's
own calendar, so seasons and the daily challenge roll over together at local
midnight.

**Active selection:** among active seasons, highest `priority` wins; ties break on
the **lexicographically smallest id**. Priority alone is not a total order, and
without the second key the winner would depend on dictionary iteration order and
could flicker between launches.

**Re-evaluate on app foreground** — an app left open across local midnight would
otherwise still show a season that ended yesterday.

### 9.5 Locale resolution for season strings

Season titles come from the payload, not from the app bundle, so the lookup has to
be tolerant. Resolve `LocalizedText` by:

1. Normalize the key set: `_` → `-`, lowercased. (Authors write `pt-BR`, Apple
   reports `pt_BR`; both must hit.)
2. Build candidates from **progressively shorter prefixes** of the device locale
   identifier, always ending in `en`. `es_419` → `["es-419", "es", "en"]`;
   `zh_Hans_CN` → `["zh-hans-cn", "zh-hans", "zh", "en"]`.
3. First hit wins. No hit ⇒ app-side fallback title ("Season") and empty subtitle.

> **This was a real shipped bug.** The lookup only ever *shortens* the identifier,
> so an `es-419` key was reachable only from a device reporting exactly `es_419` —
> never from `es_MX`, `es_AR` or `es_ES`. And a `zh-Hans` key was unreachable from
> any mainland device, because iOS canonicalizes `zh_Hans_CN` to `zh_CN` and drops
> the script. The fix was in the **catalog** (publish keys the lookup can reach:
> both `zh-Hans` and `zh-CN`, and plain `es` alongside `es-419`), with a test
> pinning every supported locale against the identifiers the OS actually produces.
> **Android reports different identifiers than iOS** (`zh-Hans-CN`, `es-419`,
> `pt-BR` via `Locale.toLanguageTag()`). Write the equivalent test for Android's
> actual output before trusting the catalog.

### 9.6 Season progress storage

Namespaced per season: `season.<id>.highestUnlocked`, `season.<id>.stars.<level>`.

- A season ending **cannot disturb** endless-Levels progress.
- A season that returns next year **resumes where it left off**.
- Completion is stored as `highestUnlocked = levelCount + 1`. This is why
  **extending a running season needs no migration** — a player who finished all 20
  levels of a season later extended to 30 simply finds level 21 unlocked and their
  progress reading 20 of 30.
- Season stars are summed on demand (bounded by `levelCount`), not stored.
- Same star thresholds as endless Levels, so a 3-star board means the same thing
  in both modes.

### 9.7 Caching and artwork

- The whole decoded catalog is **cached** locally, read **synchronously** on
  startup so the season card renders on cold launch and offline. The network read
  only ever *corrects* it. An absent or unexpected `/seasons` node leaves the
  cached catalog in place rather than wiping it.
- Only already-validated seasons are ever written to the cache, so a cache that no
  longer decodes is treated as absent rather than partially trusted.
- When the active season changes to a **new, non-nil** season, prefetch its three
  artwork URLs (card, background light, background dark) so the surfaces don't
  flash flat colour. Guard on "changed" — this runs on every foreground.
- Images are cached in **memory** (evicted under pressure) and on **disk**
  (~64 MB budget, LRU eviction, SHA-256 of the URL as the filename), with an
  in-flight de-duplication map so concurrent requests for the same URL share one
  fetch.
- **Season art is never bundled.** Seasons are published without an app release,
  so art in the binary would only cover seasons that existed at build time, and
  every player who hadn't updated would see the *previous* season's picture behind
  the new season's levels.
- **Artwork URLs are permanent contracts.** They are served with
  `Cache-Control: public, max-age=31536000, immutable`. Replacing a season's art
  requires publishing at a **new filename**; never overwrite the bytes at an
  existing URL — clients and CDNs are entitled to cache them forever.
- Dark mode takes `backgroundImageURLDark` when present, else the main background.
  One image cannot serve both: level tiles are near-white in light mode and
  near-black in dark, so artwork that separates from them in one appearance
  collapses into them in the other. The **card** takes one image, not a pair — it
  is the accent colour with white text in both appearances.

### 9.8 Publishing tooling

`firebase/scripts/upload_seasons.py` validates `firebase/scripts/seasons.json` against the **same
rules the app applies** and publishes to Firebase `/seasons`. `--dry-run`
validates without credentials. This exists so a season that would be silently
skipped on device is rejected before upload. Android needs no new tooling — the
same catalog serves both platforms — but the Android decoder must implement the
same rules or the two platforms will disagree about which seasons are valid.

Note the deliberate duplication: the Python script hardcodes the 12-emoji floor
and will **not** follow a retuned curve. Change both together.

---

## 10. Multiplayer

Two-player, turn-based, real-time over Firebase Realtime Database.

### 10.1 Database layout

```
/multiplayerRooms/{roomId}      the room document
/multiplayerRoomCodes/{CODE}    -> roomId   (a lookup index)
```

### 10.2 Room document

```
{
  id, code,
  status: waiting | ready | playing | reconnecting | finished | abandoned,
  createdAt, updatedAt,          // epoch seconds
  hostId, guestId,
  players: { <uid>: { id, name, connected, lastSeenAt, score, isReady } },
  gameSource: firebase | custom,
  gameId, gameName, difficulty,  // gameId/gameName/difficulty are "" until the host picks a game — see 10.4
  customGamePayload: { title, category, items, itemType, isDoubleItem } | null,
  currentPlayerId,
  cards: [ { id, itemId, content, isFaceUp, isMatched } ],
  selectedCardIds: [Int],        // 0, 1 or 2 entries
  winnerId,
  disconnectStartedAt, disconnectPlayerId
}
```

`customGamePayload` exists because a custom memorama lives only on the host's
device — the whole card set has to travel with the room or the guest has nothing
to render.

`gameId == ""` is the wire sentinel for "no game chosen yet" — deliberately a
plain empty string on an already-required field rather than a new optional/null
field, so a client that predates this doesn't need a schema migration and still
decodes the room; it just has no UI for the empty-game state. `gameName` and
`difficulty` are empty alongside it and are meaningless until `gameId` is
non-empty. A room only ever has an empty `gameId` in `waiting`/`ready` — it is
never empty once `status` reaches `playing`.

`players.<uid>.isReady` is a per-player flag, `false` unless explicitly set true.
Decode it defensively (default `false` when the key is absent) — a room written
before this field existed, or briefly during a mixed-version rollout, has no
`isReady` key on its player nodes at all.

### 10.3 Room codes

6 characters from the alphabet **`ABCDEFGHJKLMNPQRSTUVWXYZ23456789`** — no `I`,
`O`, `0`, `1`, to keep codes readable and dictatable. Generation retries up to 12
times against the codes index for uniqueness, then gives up and uses the last one.

Input is trimmed and uppercased before lookup.

### 10.4 Flow

Hosting is **host-first**: a room is created empty, with no game chosen, and the
host picks the game from inside the lobby — any time before or after a guest
joins, and changeable again right up until the match actually starts. This
replaced an earlier "pick a game, then create its room for it" flow; there is no
longer a way to create a room already bound to a specific board.

1. **Create** — host authenticates anonymously, allocates a room id, generates a
   unique code, writes the room in `waiting` with `gameId`/`gameName`/`difficulty`
   all `""` and `gameSource: firebase` (ignored until a game is picked), writes
   the code index, and registers presence. Takes no board.
2. **Join** — resolve `code → roomId`, load the room. Reject unless status is
   `waiting` or `ready`. Reject if a *different* guest already holds it (re-joining
   as the same uid is allowed — this is how reconnect works). On success the guest
   is added, status becomes `ready`. A guest can join a room that has no game
   chosen yet; the lobby shows a "waiting for the host to choose a game" message
   until the host picks one.
3. **Select game** (host only, any `waiting`/`ready` room) — sets
   `gameSource`/`gameId`/`gameName`/`difficulty`/`customGamePayload` from the
   chosen board. Does **not** touch `status`, `cards`, `currentPlayerId`, or
   `players` — no cards are dealt and nothing else changes; the room stays
   `waiting`/`ready`. Picking or changing the game resets every current player's
   `isReady` to `false`, since readiness was for whatever game was picked before.
   The game picker offers its own difficulty filter (independent of whatever
   difficulty the catalog tab happens to be showing) across every difficulty, not
   just the currently-filtered catalog; custom memoramas always show regardless
   of the filter.
4. **Ready check** — once a game is picked, *either* player (host or guest, once
   both have joined) may mark themselves ready. This does not itself start the
   match. Picking/changing the game (step 3) resets both players back to not
   ready.
5. **Start** — happens automatically, host-side only, the moment the room's
   state satisfies all of: `status == ready`, `gameId` non-empty, exactly two
   players present, and every player's `isReady` is `true`. No separate manual
   "start" action exists once both are ready — the host's client reacts to that
   condition and deals cards, sets `currentPlayerId` to the host, and flips
   `status` to `playing`. Guard against re-triggering while an earlier start
   write is still in flight (e.g. an unrelated presence heartbeat landing in that
   window must not cause a second deal) — reset that guard whenever `status`
   leaves `ready`.
6. **Turn** — only `currentPlayerId` may act. A tap is rejected unless the card
   exists, is neither matched nor face-up, and fewer than 2 cards are selected.
   - 1st selection: card face up, added to `selectedCardIds`.
   - 2nd selection, **match**: both matched, **current player's score +1**,
     selection cleared, **the same player keeps the turn**.
   - 2nd selection, **mismatch**: turn passes to the other player. The client
     clears the two face-up cards after its own delay.
   - When every card is matched: status `finished`, `winnerId` computed.
7. **Winner** — highest score. Sorted by score desc, id asc for stability. If the
   top two scores are **equal**, `winnerId` is `null` (a draw).
8. **Rematch** — host can restart with the same board or choose another game.
   This is a separate, host-only, immediate action (unlike step 3) — a rematch
   redeals cards and returns straight to `playing` without going through the
   ready check again.
9. **Leave** — from `waiting`/`ready`, the room becomes `abandoned`. From
   `playing`, the player is just marked disconnected.

### 10.5 Presence and reconnect

- Each player registers an **on-disconnect** write setting
  `players/<uid>/connected = false` and stamping `lastSeenAt` — the server does
  this when the socket drops, so a killed app is detected without a heartbeat.
  (Firebase Android has the same `onDisconnect()` API.)
- When a player goes missing during `playing`, status becomes `reconnecting` and
  `disconnectStartedAt` is stamped.
- **15-second grace period.** If they return, status goes back to `playing` and
  the disconnect fields are cleared. If not, the room is `finished` and the
  **remaining player wins**.

### 10.6 Security rules

```jsonc
"/data":    { ".read": true, ".write": false }
"/seasons": { ".read": true, ".write": false }
"/multiplayerRooms/$roomId": {
  ".read":  "auth != null && (hostId == auth.uid || guestId == auth.uid || !data.exists())",
  ".write": "auth != null && (!data.exists() || hostId == auth.uid || guestId == auth.uid
             || (guestId does not exist && newData.guestId == auth.uid))"
}
"/multiplayerRoomCodes/$code": { ".read": "auth != null", ".write": "auth != null" }
```

Everything requires **anonymous Firebase Auth**. The `/seasons` read rule must be
**deployed separately** (`firebase deploy --only database`) — committing the rules
file does not publish it.

### 10.7 Sharing an invite

Share text = caption + custom-scheme link + App Store link:

```
I challenge you to a memory match in DoMemory! Join my room with code ABC123:
domemory://join/ABC123
https://apps.apple.com/app/id1533115091
```

The App Store link is there so a friend without the app can install first. **The
Android version must send a Play Store link** (and ideally detect the platform, or
send both). Also offered as a **QR code** of the same link.

---

## 11. Deep links and routing

### 11.1 Link forms accepted

| Form | Purpose |
|---|---|
| `domemory://join/CODE` | custom scheme, works for installed users, no server needed |
| `https://domemory.app/join/CODE` | universal/app link — the install-then-route flow for new users. **Parser already accepts it; the association file was never deployed.** |
| any of the above with `?code=CODE` | query-parameter fallback |
| `domemory://daily` or `.../daily` | open today's Daily Challenge (the widget uses this) |
| `domemory://season/<id>` or `.../season/<id>` | open that season's level map (the App Store in-app event uses this); `domemory://season` opens whichever season is active |

Code extraction: gather the host (custom scheme only) plus path components, find
the token after `join`, else read `?code=`. Uppercase, strip non-alphanumerics,
require **exactly 6** characters.

Routing goes through a small singleton router that holds the pending code until
the Menu is ready to consume it — links can arrive before the UI exists.

The daily deep link is a no-op if today's challenge is already completed.

A season link only ever opens the **active** season: an id naming any other season (one that
has ended, or one the device has never seen) is dropped and the player stays on the Menu. On a
first launch the link can arrive before the season catalog; the request then waits for an active
season for at most **30 seconds**, then is dropped, so a season becoming active later never
pulls the player into it unasked.

**Android:** implement as an `intent-filter` for scheme `domemory` plus an App
Links filter for `domemory.app` (which needs `assetlinks.json` hosted — the
equivalent gap iOS left open).

### 11.2 Local notifications

Three scheduled reminders, all gated on a `notificationsEnabled` preference that
is **separate from OS permission**:

| Reminder | When | Body |
|---|---|---|
| Inactivity, tier 1 | 2 days from now, **19:00** local | "Time to play! / You haven't played DoMemory in a while..." |
| Inactivity, tier 2 | 7 days from now, **19:00** local | same copy |
| Streak at risk | **today at 20:00**, only if it is still in the future | "Don't break your streak! / Your %d-day streak ends tonight..." |

- Two inactivity tiers exist so a user who ignores the first nudge still gets a
  later one. Both are rescheduled (cancel + re-add) after **every game finish**.
- The streak reminder is only scheduled when `currentStreak > 0` **and** today's
  challenge is not yet done. Refreshed on launch, on foreground, and after every
  daily completion.
- **The permission bug worth not repeating:** granting OS permission is not
  enough. Every scheduling method early-returns on `notificationsEnabled`, so a
  grant that skips setting that flag leaves the user authorized and silently
  un-reminded. Route every grant path through one `activateReminders()` function
  that sets the flag *and* arms every reminder.
- On launch, sync the flag with OS state: if the app thinks reminders are on but
  the OS says denied, turn the flag off and cancel everything.

### 11.3 The permission primer

Before the OS permission dialog, show a **custom explainer** ("Keep your streak
alive") listing what reminders are for, with a fake notification preview and
"Turn On Reminders" / "Maybe Later". Shown **once per install** on the menu, and
reused by the Settings toggle.

Rationale: the OS dialog can only be shown once, ever. Spending it on a cold ask
wastes it.

### 11.4 The launch-sequence ordering problem

This is the single most fiddly part of the app and is worth porting deliberately.
On first menu appearance the app must sequence:

1. Wait until the app is actually **active** (not launching in the background).
2. Ad consent (Google UMP): refresh the consent status and show the form if
   required. Only AdMob's "European regulations" message is published, so the
   form appears only in the EEA, the UK and Switzerland; everywhere else this
   step returns with nothing on screen. No ad request of any kind (banner,
   native, interstitial, rewarded, app-open) may be made while
   `canRequestAds` is false. A network failure keeps the last stored status.
3. iOS only: the ATT prompt, requested only while its status is
   `.notDetermined`. Android has no equivalent step.
4. Start the ads SDK, **only after** the steps above and only if
   `canRequestAds`. On iOS, starting before ATT resolves marks requests
   non-personalized even when the user later grants permission.
5. Notification permission primer, if due.
6. Only then mark the launch sequence finished, which unblocks the Levels intro.

Settings shows a **Privacy options** row that reopens the consent form, only
while the SDK reports `privacyOptionsRequirementStatus == REQUIRED`.

Meanwhile: the **What's New sheet** and the **notification primer** each suppress
full-screen ads while they are on screen, because the app-open ad rides
"app became active" — which fires *again* the moment a system dialog is dismissed,
landing the ad directly on top of the release announcement.

---

## 12. Monetization

### 12.1 Ad placements

| Placement | Format | Where |
|---|---|---|
| `home_banner` | banner | menu, above the tab bar |
| `game_banner` | banner | gameplay, below the board |
| `game_finished_interstitial` | interstitial | after a game finishes |
| `game_rewarded_extra_time` | rewarded | lose screen → +30 s |
| `game_rewarded_hint` | rewarded | pause screen → reveal one pair |
| `levels_rewarded_life` | rewarded | out of lives → +1 life |
| `levels_rewarded_forgive` | rewarded | mistake bust → forgive 3 |
| `app_open` | app-open | on foreground |
| `multiplayer_finished_native` | native | multiplayer end screen |
| `ad_free_day_rewarded` | rewarded | ad-free day sheet (pill on menu tabs, season map, multiplayer lobby; Settings row) → two ads = 24 h without involuntary ads |

Ad unit ids are per-platform — **Android needs its own AdMob app id and its own
unit ids.** Do not reuse the iOS ones. The iOS app id is
`ca-app-pub-4297174845441653~4688728438`; the account is the same, the units are
not.

Debug builds use Google's public test unit ids; release builds use real ones, and
a placement with an **empty** release id is treated as unconfigured (the feature
that depends on it hides itself, rather than failing at present time).

### 12.2 Frequency capping

The rules that stop the app feeling like an ad delivery mechanism:

- **Interstitial after a game:** shown every **3** completed games on easy/medium,
  every **2** on hard/very hard. The counter persists; it resets to 0 only when an
  ad is actually *presented*, and if the ad isn't loaded yet the request is queued
  and fires as soon as it loads.
- **Not shown** if the game lasted **< 20 seconds** (a rage-quit doesn't earn an
  ad), or if a rewarded ad was watched **within the last 60 seconds**.
- **Never** after a paid outcome (a 15★ skip).
- **90-second minimum** between any two full-screen ads of any kind.
- **App-open ad:** only after the menu has signalled it is ready, only if no other
  full-screen ad is presenting, only if no first-run surface is up, and only if
  the cached ad is **fresher than 4 hours**.

### 12.3 Remove Ads (deferred on Android) and the ad-free day (ported)

The non-consumable `com.ezequielbrrt.domemory.removeads` product and its restore
flow are still intentionally absent from Android. The rewarded ad-free day below is
ported (2026-09-30), with two differences that follow from the missing purchase: the
sheet has no "Remove ads forever" link, and the Settings "Purchases" section holds
only the ad-free day row. Android's ad-free window lives in its own preference,
since there is no `hasRemovedAds` purchase to combine it with; `AdFreeGate` is the
read side the ads layer consults. `ad_free_day_rewarded` shares Android's single
rewarded unit.

**Ad-free day (iOS 4.4.0).** Watching **two** rewarded ads
(`ad_free_day_rewarded`), each on its own tap, sets a 24-hour expiry during which
`hasRemovedAds` is true and every *involuntary* placement (banners, natives,
interstitials, app-open) is suppressed. Rewarded placements stay available.

- **Entry points:** a floating capsule pill, bottom-trailing, on the three menu
  tabs, the season map and the multiplayer lobby (never on gameplay, modals or the
  multiplayer board). Hidden for Remove Ads purchasers, and when the rewarded unit
  is unconfigured unless a grant is running. Pill text: "No Ads" idle, "No Ads 1/2"
  mid-chain, "18h left" while active (one unit, hours or minutes). The Settings row
  "Free ad-free day" opens the same sheet.
- **Sheet:** Flippo illustration, title, message, a three-node stepper
  (Ad 1 → Ad 2 → Ad-free day), one primary button, a "Remove ads forever · price"
  link to the purchase, and "Not now". The **first** presentation ever uses the
  apology copy (`ad_free_day_intro_*`); a persisted flag switches every later one
  to the neutral copy. States: loading (button disabled, "Loading ad..."), ready
  ("Watch ad N of 2"), presenting, no fill ("Try again", progress kept), active
  ("Ads are off until <time>", "Back to the game").
- **Progress:** ads watched today (0 or 1) persists in preferences keyed to the
  local day seed (same as lives); it resets on the first read of a new day and
  after a completed chain. One ad grants nothing. The second ad is never
  auto-launched after the first closes.
- **Grant:** extends the existing `rewardedRemoveAdsExpirationDate` by 24 h from
  now, or from the current expiry when one is still running.
- **Analytics**, in funnel order:
  `ad_free_day_entry_tapped{source, state (idle/in_progress/active), ads_watched}`
  on a tap of the pill or the Settings row;
  `ad_free_day_offer_shown{source, is_intro (1/0), ads_watched}` when the sheet
  appears; `ad_free_day_watch_tapped{source, ad_number}` when "Watch ad N of 2"
  is tapped with an ad ready; `ad_free_day_ad_watched{source, ad_number}` when
  ad N pays out (read `ad_number` before recording it — completing the chain
  clears progress); `ad_free_day_granted{source}` after the last ad. Plus
  `ad_lifecycle` for the ad itself under placement `ad_free_day_rewarded`.
  Sources: `menu_levels`, `menu_mine`, `menu_all`, `season_levels`,
  `multiplayer_lobby`, `settings`.
- **Constants:** required ads 2, grant 24 h, both plain constants (candidates for
  Remote Config later).

---

## 13. Data, storage and backend

### 13.1 Firebase Realtime Database `/data` — the board catalog

An **array** (not a dictionary) of board objects:

```jsonc
{
  "id": "1",
  "name": "😁",
  "category": "emoji",
  "description": "emoji",
  "difficulty": "easy",              // easy | medium | hard | veryHard
  "publishedDate": "10-02-2021",
  "items": ["😀","😃","😄","😁"],
  "itemType": "String",
  "isDoubleItem": true
}
```

~134 entries. Read once per menu load with a single snapshot, shuffled, then
filtered to the player's difficulty and merged with local custom boards.

Failure is silent and non-fatal: no Firebase, no auth, or an unexpected payload
leaves the list empty and the app usable (Levels and custom boards still work).

`firebase/scripts/gamesToJson.py` converts `games.csv` → `data.json` for seeding.

### 13.2 Local storage

| Store | Key | Contents |
|---|---|---|
| CoreData | `UserSettings` | `dificulty` (sic), `points` (unused). One row. Its **existence** is the "has onboarded / is an existing user" marker. |
| Prefs | `dificulty` | (legacy key, superseded by CoreData) |
| Prefs | `favoriteIDs` | `[String]` of favourited board ids |
| Prefs | `customMemoramas` | JSON array of player-created boards |
| Prefs | `themePreference` | `system` / `light` / `dark` |
| Prefs | `hapticsEnabled` | **defaults to true** — must be read as "value or true", not "bool or false", or the whole feature ships silently disabled |
| Prefs | `notificationsEnabled` | app-level reminder toggle |
| Prefs | `notificationPrimerShown` | one-shot |
| Prefs | `whatsNewLastSeenVersion` | version-gate for the release sheet |
| Prefs | `onboardingIntroShown`, `levelsIntroShown` | one-shot carousels |
| Prefs | `seasonCatalog` | cached `/seasons` payload |
| Prefs | `stats.<boardId>.played` / `.won` | per-board counters |
| Prefs | `profile.totalPlayed`, `.totalWon`, `.perfectGames`, `.multiplayerWins`, `.bestRemaining.<difficulty>` | lifetime aggregates |
| Prefs | `levels.highestUnlocked`, `levels.stars.<n>`, `levels.lifetimeStars`, `levels.wallet.balance` | endless Levels |
| Prefs | `levels.lives.remaining`, `levels.lives.lastResetDay` | daily lives |
| Prefs | `season.<id>.highestUnlocked`, `season.<id>.stars.<n>` | per-season |
| Prefs (shared) | `dailyStreakCurrent`, `dailyStreakLongest`, `dailyLastCompletedDay`, `dailyLastAttemptDay` | daily challenge — shared with the widget |
| Prefs | `purchases.has_removed_ads`, `purchases.rewarded_remove_ads_expiration_date` | entitlements |
| Prefs | `ads.game_finished_interstitial_completion_count` | frequency counter |

**Android:** all of the above fits comfortably in a single DataStore Preferences
file plus one shared file for widget state. CoreData's single row is not worth a
Room database — but keep "a settings record exists" as the onboarding marker, or
invent an explicit `hasOnboarded` flag and be consistent.

### 13.3 Custom memoramas

- Created from a sheet: a name and 2+ emoji, added one at a time.
- Stored as JSON in preferences with an id prefixed `custom_` — that prefix is
  how the rest of the app identifies a custom board (analytics `is_custom`,
  multiplayer `gameSource`, the "My memoramas" tab filter).
- They **ignore difficulty filtering** — they always appear in "My memoramas"
  regardless of the current difficulty setting.
- Deleting one also clears its per-board stats.

### 13.4 Favourites

A set of board ids. Favourited boards sort to the top of their tab. Toggled from
the grid cell.

---

## 14. Presentation

### 14.1 Colour palette

Every colour is defined as a **light/dark pair** and resolved from the active
appearance. Values are 8-bit RGB.

| Token | Light | Dark |
|---|---|---|
| `primary` | `75, 63, 200` | `142, 129, 255` |
| `secondary` | `255, 99, 64` | `255, 134, 109` |
| `easyGreen` | `40, 182, 126` | `73, 214, 151` |
| `hardAmber` | `245, 166, 35` | `255, 193, 87` |
| `freezeBlue` | `0, 145, 199` | `94, 200, 245` |
| `appBackground` | `247, 243, 237` | `17, 19, 31` |
| `surfacePrimary` | `255, 255, 255` | `30, 34, 52` |
| `surfaceSecondary` | `239, 233, 227` | `40, 46, 69` |
| `surfaceBorder` | `225, 219, 235` | `65, 72, 98` |
| `textPrimary` | `28, 24, 48` | `244, 240, 255` |
| `textSecondary` | `122, 114, 145` | `164, 171, 196` |
| `shadow` | `28, 24, 48` @ 8% | `0, 0, 0` @ 32% |
| `overlayBackdrop` | `247, 243, 237` @ 88% | `9, 11, 18` @ 74% |

Theme is user-selectable: **System / Light / Dark**, applied app-wide.

### 14.2 Typography

Two named styles are used throughout:

- **`righteous(size:)`** — the display/brand face (app title, win headings).
- **`patrickHand(size:)`** — the secondary/handwritten face.

**Important:** although `Righteous-Regular.ttf` and `PatrickHand-Regular.ttf` are
bundled and declared, the actual implementations return **system fonts** — heavy
rounded and semibold rounded respectively. The custom faces are effectively not in
use: iOS renders SF Pro Rounded, which Apple licenses for Apple platforms only.
Android keeps the two-role structure and renders both roles, and every Material
text style, in **Nunito** (a rounded sans, SIL OFL 1.1, bundled as one variable
`res/font/nunito.ttf` with its licence in `assets/licenses/`): `display` at
`ExtraBold`, `handwritten` at `SemiBold`. It is the closest freely licensed match
for SF Rounded, not the same face.

Body UI uses rounded system fonts at weights `semibold`/`bold`/`heavy`.

### 14.3 Visual language

- Rounded rectangles, `cornerRadius: 12–16`, `.continuous` style.
- Surfaces are `surfacePrimary` filled, `surfaceBorder` 1 pt stroked, with a soft
  shadow (`radius 6, y 3`).
- Chips are capsules with 14 pt horizontal / 8 pt vertical padding.
- Icons are SF Symbols; map each to a Material Symbol on Android
  (`timer`, `snowflake`→`ac_unit`, `eye.fill`→`visibility`, `star.fill`→`star`,
  `xmark.circle.fill`→`cancel`, `trophy.fill`, `person.2.fill`→`group`,
  `shuffle`, `flame.fill`→`local_fire_department`, `rosette`→`military_tech`).
- Numeric values that change in place (star balance, timer) use a numeric text
  transition.

### 14.4 Haptics

A single service maps **moments** to feedback, so the whole feel can be retuned in
one table rather than at 60 call sites. Defaults **on**, toggleable in Settings.

| Intent | When | iOS feedback | Android equivalent |
|---|---|---|---|
| `tap` | any button or row | impact light | `HapticFeedbackConstants.CONTEXT_CLICK` |
| `select` | picker change, level tile, turn handover | selection | `CLOCK_TICK` / `SEGMENT_TICK` |
| `cardFlip` | first card of a pair turned over | impact soft | light `VibrationEffect` tick |
| `match` | pair resolved | impact medium | medium click |
| `mismatch` | pair missed | impact rigid | sharper click |
| `success` | level cleared, game won | notification success | `CONFIRM` / composed effect |
| `failure` | level lost, out of lives | notification error | `REJECT` |
| `warning` | action refused, purchase failed | notification warning | `REJECT` |
| `reward` | stars earned, life granted, ad rewarded | impact heavy | heavy click |

Details that matter:

- Generators are **held for the app's lifetime**, not constructed per call — a
  cold haptic engine adds latency you can feel on the very first tap, which is
  exactly the tap that matters.
- The next likely feedback is **pre-warmed** (after a card flip, warm the next
  card flip).
- **A dead tap must not buzz.** Taps on already-face-up or already-matched cards
  are ignored by the model — the haptic fires only if something actually changed.
- **The final match is silent.** It is followed within milliseconds by the win
  pattern, and a thud in front of that reads as a stutter.
- A loss fires exactly once, on the transition into the loss — not on restarts or
  rescues.

### 14.5 Accessibility

- The fails chip announces "N of M mistakes used"; the timer announces
  "Timer frozen, N seconds left" **only while frozen** (an always-on label would
  replace the icon-plus-number screen readers read by default with a bare,
  contextless number).
- The star balance announces "N stars available"; power-up buttons announce
  "<name>, costs N stars".
- The season progress bar announces "7 of 20 levels cleared" rather than "7 / 20".
- Cards announce what the player would see, not the drawn glyphs. A face-down
  card reads "Face-down card" (not "question mark") and offers a "Flip" action.
  A face-up card reads its emoji with the state "Face up", or "Matched" once its
  pair is found, and offers no action, because tapping it does nothing. A matched
  card that has left the board is removed from the accessibility tree; it is only
  transparent, so a screen reader would otherwise still find it. Both platforms
  share the `game_card_*` keys. On iOS a face-down card's emoji is still in the
  view tree at zero opacity, so the label must replace it, never sit beside it.
- Disabled controls stay silent — the haptic modifier sits inside the disabled
  subtree.

---

## 15. Engagement surfaces

### 15.1 What's New

Shown **once per version upgrade**, comparing the running version against a stored
`whatsNewLastSeenVersion`.

- A **brand-new install records the running version immediately** and never sees
  the sheet — greeting a first-time player with release notes for a version they
  have never not had is a bug that shipped once.
- But "no stored version" alone cannot detect a new install: someone upgrading
  from a build that predates the feature also has nothing stored, and they
  **should** see it. **Onboarding state is what separates the two.**
- Marked seen on **dismiss**.
- **iOS gates on the notes, not the version (since 4.5.0):** the sheet shows only while the stored
  version is older than `WhatsNewManager.releaseNotesVersion`, the release its items describe (also
  its badge), so a fixes-only release does not re-show old notes. Android, unreleased and on its own
  version line, still gates on the running version; adopt the same rule with an Android notes version
  before its first update that has nothing new to announce.
- Reopenable from a Settings row.
- Suppresses full-screen ads while up.

Current 4.2.0 content: Season Levels / Themed Artwork / Tap to Play / Season
Progress.

### 15.2 Review prompts

A conservative in-app review flow. A **successful game win** is recorded as a
"successful action"; the library decides whether to actually prompt, honouring a
cooldown and a per-version cap. Settings also carries a plain **"Rate DoMemory"**
link to the store page, so leaving a review doesn't depend on catching the
throttled system prompt.

**Android:** ReviewFlow-Android (the same package's Android twin, vendored as a
submodule) with its recommended policy, presenting its full-screen review
invitation rather than Play's In-App Review sheet — Google Play has no direct
"write a review" link, so the invitation opens the listing. Same "record wins,
let the policy decide, plus an always-available link" structure.

### 15.3 Onboarding carousel

Three slides shown before the difficulty picker on first launch:
Play with Friends / Make It Yours / Come Back Daily. Skippable. Analytics
distinguish completed from skipped.

### 15.4 Achievements

A Settings sub-screen with lifetime stats and badges.

**Stats:** Games Played, Wins, Win Rate, Perfect Games, Longest Streak,
Multiplayer Wins. Plus a per-difficulty "best remaining time" (highest
`timeRemaining` on a win = fastest clear).

**Badges** (each with a 0…1 progress value):

| Badge | Unlock |
|---|---|
| 10 Wins / 50 Wins / 100 Wins | total wins ≥ threshold |
| 7-Day Streak / 30-Day Streak | longest daily streak ≥ threshold |
| Flawless | win a game with **0** mistakes |
| Champion | win your first multiplayer match |

### 15.5 Share result

A rendered card, shared as an image, showing a **spoiler-free Wordle-style grid**:
one 🟩 per pair matched, then a row of 🟧 per mistake (each capped at 12). It
reveals nothing about the actual emoji. Caption: "I matched %d pairs in DoMemory!
Can you beat me?"

---

## 16. Analytics

Firebase Analytics, with every event typed in one place — a single enum carrying
its own name and parameter dictionary, so no event name or parameter key is ever
written as a bare string at a call site. **Port this pattern**, it is the reason
the event set is consistent.

### 16.1 Event catalog

| Event | Parameters |
|---|---|
| `screen_view` | `screen_name`, `screen_class` |
| `difficulty_selected` | `difficulty` |
| `menu_loaded` | `difficulty` |
| `menu_tab_selected` | `tab`, `previous_tab` (`levels` \| `mine` \| `all`) — only on a switch; the Levels default at launch, re-tapping the current tab and the automatic jump to `mine` after creating a memorama log nothing |
| `game_list_loaded` | `difficulty`, `game_count`, `custom_count` |
| `game_started` | `source`, `difficulty`, `cards_count`, `is_custom` |
| `game_finished` | `result`, `difficulty`, `cards_count`, `failed_tries`, `time_remaining`, `is_custom` |
| `card_tapped` | `difficulty`, `cards_count`, `failed_tries` — **sampled at 20%** |
| `pause_opened` / `resume_tapped` | `difficulty`, `time_remaining` |
| `quit_confirmed` | `difficulty`, `time_remaining`, `failed_tries` |
| `retry_tapped` | `difficulty`, `cards_count`, `source` |
| `favorite_toggled` | `game_id`, `is_favorite` |
| `custom_memorama_create_opened` | `source` (`menu_header` \| `mine_empty_state`) |
| `custom_memorama_created` | `game_id`, `difficulty`, `cards_count` |
| `custom_memorama_deleted` | `game_id` |
| `multiplayer_entry_tapped` | `action` (`host` \| `join`) — the host/join choice, before the backend accepts (iOS: the menu's multiplayer menu; Android: the lobby's Create, Join and Scan QR buttons) |
| `multiplayer_room_created` | `game_id`, `is_custom` |
| `multiplayer_room_joined` | — |
| `multiplayer_game_started` | `game_id` |
| `multiplayer_game_finished` | `result` (`completed` \| `disconnect`) |
| `multiplayer_invite_sent` | `source` |
| `multiplayer_invite_opened` | — |
| `ad_lifecycle` | `placement`, `action` (`requested` \| `reward_earned` \| `dismissed_rewarded` \| `dismissed_unrewarded`) |
| `whats_new_shown` / `_dismissed` / `_opened_from_settings` | `version` |
| `notification_primer_shown` | `source` |
| `notification_primer_completed` | `source`, `outcome` |
| `review_link_opened` | `source` |
| `daily_challenge_opened` | `source` (`card` \| `widget` — the `daily` deep link), `streak` — once per entry; `daily_challenge_started` repeats on every retry |
| `daily_challenge_started` | `streak` |
| `daily_challenge_finished` | `result`, `streak` |
| `streak_milestone` | `days` |
| `result_shared` | `source` |
| `onboarding_intro_completed` / `_skipped` | — |
| `achievements_opened` | `source` (`settings`) |
| `theme_changed` | `theme`, `previous_theme` (`system` \| `light` \| `dark`) — only when the pick differs |
| `level_started` | `level` (+ `season_id`) |
| `level_finished` | `level`, `result`, `stars`, `power_ups_used` (star power-ups bought this attempt) (+ `season_id`) |
| `level_unlocked` | `level` (+ `season_id`) |
| `level_life_consumed` / `level_life_granted_from_ad` | `lives_remaining` |
| `level_lives_depleted` | `level` (+ `season_id`) — a loss just spent the last life |
| `level_out_of_lives_shown` | `source` |
| `level_stars_credited` | `level`, `amount`, `balance_after` (+ `season_id`) |
| `level_power_up_used` | `power_up`, `level`, `cost`, `balance_after` (+ `season_id`) |
| `level_life_purchased_with_stars` | `cost`, `balance_after` |
| `level_skipped` | `level`, `cost`, `balance_after` |
| `level_failed_by_mistakes` | `level`, `max_failures`, `time_remaining` |
| `level_mistakes_forgiven` | `level`, `amount`, `source` (`ad` \| `stars`) |
| `levels_intro_shown` | `source` |
| `levels_intro_completed` | — |
| `levels_intro_skipped` | `slides_seen` (1-based) |
| `season_card_tapped` | `season_id` — the menu card; `season_levels_entered` also fires on returning from a level |
| `season_levels_entered` | `season_id` |

### 16.2 The season dimension

Season play **reuses the numbered-level events** rather than getting a parallel
set, so the season and endless funnels stay directly comparable. `season_id` is
added as a parameter when a season owns the level, and the key is **omitted
entirely** (not sent empty) for endless Levels — so an endless event is
byte-identical to what it was before Seasons existed, no historical comparison
breaks, and `season_id is null` cleanly means "endless".

`season_levels_entered` exists separately because the generic `screen_view`
carries no season identity, so a season's own entry funnel could not be filtered.

### 16.3 Two counting rules

- **`level_unlocked` means "a new playable level became available."** Completing a
  season stores `levelCount + 1` as the highest unlocked level, and logging that
  number would emit one unlock for a level that does not exist, on every completed
  season. Gate it on `nextLevel(after:)` being non-nil. Season completion stays
  derivable from `level_finished` with `level == levelCount`.
- **Game-finish recording is idempotent.** Stats, streaks, lives, star credits and
  the finish event all run through one guarded function so a win can never
  double-count.

---

## 17. Localization

Ten locales: `en`, `es-419`, `pt-BR`, `de`, `it`, `fr`, `hi`, `ja`, `ko`,
`zh-Hans`. **Every** user-facing string goes through a typed accessor — no bare
literals in views. ~250 keys.

Format strings use positional arguments where more than one is present (e.g.
`"%1$d of %2$d mistakes used"`), which Android's `getString` supports identically.

A **localization parity test** exists and should be ported: it asserts that every
locale defines every key the base locale defines. Missing keys silently fall back
to the key name at runtime, which is invisible until a user in that language sees
it.

The full English catalog is in §19.

---

## 18. Build order recommendation

The iOS app grew feature by feature; a port can be sequenced more sensibly. Each
phase below is independently shippable and testable.

**Phase 1 — the game.** Board model, matching rules, timers, the gameplay screen,
difficulty, the free-play mode with a hardcoded board list. No backend, no ads.
This is where the unit tests for the model and the level curve go.

**Phase 2 — catalog and menu.** Firebase anonymous auth, `/data` read, the menu
with tabs, favourites, custom memoramas, per-board stats, onboarding, settings,
theme. Localization structure from the start — retrofitting it is miserable.

**Phase 3 — Levels.** The curve, the map, stars, both star counters, daily lives,
the mistake budget, power-ups, the star purchases, the intro carousel. This is the
largest single phase and the one that most defines the product.

**Phase 4 — Seasons.** The `LevelProgressStore` abstraction, the catalog service
with its cache, validation, artwork loading, the season card and map. Much cheaper
if Phase 3 built the store seam rather than hardcoding endless Levels.

**Phase 5 — Daily Challenge + widget + notifications.** Deterministic generation,
streaks, the Glance widget, reminders, the permission primer.

**Phase 6 — Multiplayer.** Rooms, codes, QR, presence, reconnect, invites, deep
links.

**Phase 7 — Monetization.** AdMob placements and frequency caps, Play Billing,
the rewarded ad-free day. Do the frequency capping properly the first time.

**Phase 8 — Engagement polish.** What's New, review prompts, achievements, share
cards, haptics, animations.

### Parity decisions to make explicitly, up front

1. **Daily Challenge board parity** — does Android have to generate the identical
   board to iOS? (§6.1.) If yes, verify the shuffle empirically before Phase 5.
2. **Progress migration** — is there any path for an existing iOS player to carry
   progress to Android? Today all progress is device-local with no account.
   If cross-device progress ever matters, an account layer has to be designed;
   it does not exist today and retrofitting it over device-local preferences is
   significant work.
3. **App Links** — `domemory.app` has no association file deployed on either
   platform. Deploying `assetlinks.json` (Android) and `apple-app-site-association`
   (iOS) at the same time is cheaper than doing it twice.
4. **Invite share text** — must send a Play link for Android recipients (§10.7).
5. **AdMob** — a separate Android app and separate unit ids are mandatory.
6. **Firebase** — add an Android app to the existing `domemory-c9211` project so
   both platforms read the same `/data`, `/seasons` and multiplayer rooms.
   **Multiplayer must be cross-platform** — the room format is
   platform-independent already, so an Android player and an iOS player can and
   should be able to play each other. Verify this explicitly; it is the single
   highest-value cross-platform behaviour in the app.

### Existing test coverage worth mirroring

`MemoryGameTests`, `MemorizeViewModelTests`, `LevelCurveTests`,
`LevelProgressServiceTests`, `LevelLivesServiceTests`, `StarWalletServiceTests`,
`LevelsIntroGateTests`, `SeasonTests`, `SeasonCatalogServiceTests`,
`SeasonProgressServiceTests`, `SeasonLevelsViewModelTests`, `SeasonGameModeTests`,
`HapticsServiceTests`, `RemoteImageServiceTests`, `WhatsNewManagerTests`,
`LocalizationParityTests`.

The pure logic — curve, stars, lives, wallet, season validation, locale
resolution, day boundaries — is all testable without a UI and is where the real
bugs live.

---

## 19. String catalog (English base)

These are the exact keys and English values shipping in 4.2.0. Keys are already
snake_case and translate directly to `strings.xml` names. Positional format
specifiers (`%1$d`) work unchanged on Android; bare `%d` / `%@` become `%d` / `%s`.

```properties
# Common
common_accept = Accept
common_app_name = DoMemory
common_cancel = Cancel
common_delete = Delete
common_ok = OK

# Difficulty
difficulty_easy = Easy
difficulty_easy_subtitle = Relaxed start
difficulty_medium = Medium
difficulty_medium_subtitle = A fair challenge
difficulty_hard = Hard
difficulty_hard_subtitle = Sharpen your memory
difficulty_very_hard = Very hard
difficulty_very_hard_subtitle = Only for experts
home_difficulty_title = Difficulty
home_select_difficulty_prompt = Select difficulty

# Gameplay
game_continue = Continue
game_go_to_menu = Menu
game_lose_message = Sorry, you ran out of time
game_pause_title = Pause
game_pairs_label = pairs
game_points_label = Points
game_quit_accessibility = Quit game
game_quit_confirmation = Are you sure you want to exit?
game_remaining_label = remaining
game_errors_label = errors
game_time_label = Time
game_try_again = Try again
game_win_title = Congratulations!
game_win_description = You finished this memorama in time
game_rewarded_extra_time = Watch ad to add 30s
game_rewarded_hint = Watch ad for a hint
ads_loading = Loading ad...
ads_label = Ad

# Levels
levels_screen_title = Levels
level_title_format = Level %d
levels_current_level_format = Currently on level %d
level_cleared = Level Cleared!
level_next = Next Level
level_back_to_levels = Back to levels
levels_out_of_lives_title = Out of Lives!
levels_out_of_lives_message = Watch an ad for +1 life, or come back tomorrow for a fresh set.
levels_out_of_lives_message_no_ad = Spend stars for another life, or come back tomorrow for a fresh set.
levels_watch_ad_for_life = Watch ad for +1 life
levels_lives_remaining_format = %d of %d lives remaining

# Levels star economy
levels_powerup_extra_time = +15s
levels_powerup_peek = Peek
levels_powerup_freeze = Freeze
levels_powerup_reveal_pair = Reveal
levels_star_balance_format = %d stars available
levels_powerup_cost_format = %1$@, costs %2$d stars
levels_buy_life_format = Buy a life — %d
levels_skip_level_format = Skip this level — %d
levels_skip_level_confirm_title = Skip this level?
levels_skip_level_confirm_message = You'll unlock the next level, but this one stays at zero stars. You can replay it any time.
levels_skip_level_confirm_action = Skip

# Levels mistake budget
levels_lose_too_many_mistakes = Too many mistakes
levels_forgive_ad_format = Watch ad to forgive %d mistakes
levels_forgive_stars_format = Forgive %1$d mistakes — %2$d
levels_mistakes_remaining_format = %1$d of %2$d mistakes used
levels_timer_frozen_format = Timer frozen, %d seconds left

# Levels intro
levels_intro_progress_title = Endless Levels
levels_intro_progress_subtitle = Clear a level to unlock the next. Boards keep growing and the clock keeps tightening — there's always one more waiting.
levels_intro_stars_title = Earn Stars
levels_intro_stars_subtitle = Finish fast and clean to earn up to 3 stars a level, then spend them on power-ups, extra lives, or skipping a level you're stuck on.
levels_intro_lives_title = Lives Refill Daily
levels_intro_lives_subtitle = You get %d lives a day and lose one whenever a level beats you. Out of lives? Watch an ad or spend stars to keep going.
levels_intro_mistakes_title = Mind Your Mistakes
levels_intro_mistakes_subtitle = Each level allows only so many wrong matches. Hit the limit and the run ends — but you can forgive mistakes and carry on.
levels_intro_done = Got It
levels_intro_info_accessibility = How Levels works

# Seasons
season_fallback_title = Season
season_progress_format = %1$d / %2$d
season_progress_accessibility_format = %1$d of %2$d levels cleared
season_days_left_format = %d days left
season_one_day_left = 1 day left
season_last_day = Last day
season_complete_badge = Complete
season_complete_title = Season complete!
season_complete_message = You cleared every level. Replay any of them to improve its stars.

# Menu
menu_tab_levels = Levels
menu_tab_mine = My memoramas
menu_tab_all = All
menu_random_game = Random game
menu_empty_mine_message = You don't have any memoramas yet
menu_empty_mine_action = Create one
menu_create_title = New Memorama
menu_create_name_label = Name
menu_create_name_placeholder = E.g. Fruits, Animals...
menu_create_emojis_label = Emojis
menu_create_add = Add
menu_create_add_emoji = Add emoji
menu_create_minimum_hint = Minimum 2
menu_create_save = Save
stats_played_label = played
stats_won_label = won

# Daily Challenge
daily_challenge_title = Daily Challenge
daily_challenge_subtitle = New board every day
daily_challenge_completed = Done for today!
daily_challenge_streak_format = 🔥 %d-day streak

# Multiplayer
multiplayer_title = Multiplayer
multiplayer_create_room = Create room
multiplayer_join_room = Join room
multiplayer_join_description = Enter the 6-character room code from your friend.
multiplayer_code_placeholder = ABC123
multiplayer_qr_code = Multiplayer room QR code
multiplayer_start_game = Start game
multiplayer_waiting_for_player = Share this code and wait for another player
multiplayer_choose_game = Choose a game
multiplayer_host_choose_game_prompt = Choose a game to get started
multiplayer_waiting_for_game = Waiting for the host to choose a game
multiplayer_no_games_for_difficulty = No boards for this difficulty yet
multiplayer_tap_start_when_ready = Tap Start when you're ready
multiplayer_waiting_for_opponent_ready = Waiting for the other player to get ready
multiplayer_your_turn = Your turn
multiplayer_opponent_turn = Opponent's turn
multiplayer_reconnecting = Waiting for player to reconnect
multiplayer_you_won = You won
multiplayer_you_lost = You lost
multiplayer_draw = Draw
multiplayer_room_closed = Room closed
multiplayer_you = You
multiplayer_opponent = Opponent
multiplayer_final_score = Final score
multiplayer_play_again = Play again
multiplayer_waiting_for_rematch = Waiting for host
multiplayer_choose_another_game = Choose another game
multiplayer_host_name = Host
multiplayer_guest_name = Guest
multiplayer_invite_friend = Challenge a friend
multiplayer_invite_message = I challenge you to a memory match in DoMemory! Join my room with code %@:
multiplayer_generic_error = Something went wrong. Please try again.
multiplayer_error_firebase_unavailable = Multiplayer is unavailable right now.
multiplayer_error_authentication = Could not connect to multiplayer.
multiplayer_error_room_not_found = Room not found.
multiplayer_error_room_full = This room is already full.
multiplayer_error_room_unavailable = This room is no longer available.
multiplayer_error_invalid_move = That move is not available.
multiplayer_error_permission_denied = Firebase rules are blocking multiplayer rooms.
multiplayer_error_encoding = Could not prepare the room.
multiplayer_error_decoding = Could not read the room.

# Settings
settings_title = Settings
settings_description = Adjust your game preferences
settings_section_game = Game
settings_section_preferences = Preferences
settings_section_purchases = Purchases
settings_section_about = About
settings_theme_title = Theme
settings_theme_prompt = Choose your preferred appearance
theme_system = System
theme_light = Light
theme_dark = Dark
settings_haptics_title = Haptics
settings_haptics_description_on = Buttons and card matches give a small vibration.
settings_haptics_description_off = Vibration feedback is turned off.
settings_notifications_title = Reminders
settings_notifications_description_on = You'll be reminded if you haven't played in 2 days
settings_notifications_description_off = Get notified when you haven't played in a while
settings_notifications_denied_title = Notifications Disabled
settings_notifications_denied_message = Enable notifications for DoMemory in iOS Settings to receive reminders.
settings_notifications_open_settings = Open Settings
settings_review_title = Rate DoMemory
settings_review_description = Reviews help other players find the game
settings_whats_new_title = What's New
settings_whats_new_description = See what changed in the latest update

# Purchases
settings_remove_ads_title = Remove ads
settings_remove_ads_description = Remove banners and interstitials
settings_remove_ads_action_format = Buy %@
settings_remove_ads_loading = Loading
settings_remove_ads_purchased = Purchased
settings_remove_ads_purchased_description = Ads are disabled on this device
settings_remove_ads_unavailable = Remove Ads is unavailable right now
settings_remove_ads_pending = Purchase pending approval
settings_remove_ads_no_restore = No Remove Ads purchase was found
settings_rewarded_remove_ads_title = Free ad-free day
settings_rewarded_remove_ads_description = Watch %d short ads to disable ads for 24 hours
settings_rewarded_remove_ads_action = Watch
settings_rewarded_remove_ads_active = Active
settings_rewarded_remove_ads_active_format = Ads are disabled until %@
settings_rewarded_remove_ads_success_title = Ads disabled
settings_rewarded_remove_ads_success_message = Ads are disabled for the next 24 hours.
settings_restore_purchases_title = Restore purchases
settings_restore_purchases_description = Recover a previous purchase
settings_restore_purchases_action = Restore
settings_purchase_success_title = Purchase Successful
settings_purchase_success_message = Ads have been removed. Enjoy the game!
settings_restore_success_title = Purchases Restored
ad_free_day_pill_title = No Ads
ad_free_day_pill_progress_format = No Ads %d/%d
ad_free_day_pill_active_format = %@ left
ad_free_day_intro_title = Sorry about the ads
ad_free_day_intro_message = They keep DoMemory free, but here's a way out: watch %d short ads and we turn them off for the next 24 hours.
ad_free_day_intro_watch_format = Sounds fair, watch ad %d of %d
ad_free_day_title = Play a day without ads
ad_free_day_message = Watch %d short ads and we turn off banners and interstitials for 24 hours.
ad_free_day_watch_format = Watch ad %d of %d
ad_free_day_step_ad_format = Ad %d
ad_free_day_step_reward = Ad-free day
ad_free_day_halfway_hint = One more and you're done
ad_free_day_no_fill = No ad available right now. Your progress is saved.
ad_free_day_try_again = Try again
ad_free_day_active_format = Ads are off until %@
ad_free_day_back = Back to the game
ad_free_day_remove_forever_format = Remove ads forever · %@
ad_free_day_not_now = Not now
settings_restore_success_message = Your previous purchase has been restored.

# Achievements
achievements_title = Achievements
achievements_subtitle = Track your progress and badges
achievements_stats_section = Your Stats
achievements_badges_section = Badges
stat_total_games = Games Played
stat_total_wins = Wins
stat_win_rate = Win Rate
stat_perfect_games = Perfect Games
stat_longest_streak = Longest Streak
stat_multiplayer_wins = Multiplayer Wins
ach_wins_title_format = %d Wins
ach_wins_detail_format = Win %d games
ach_streak_title_format = %d-Day Streak
ach_streak_detail_format = Reach a %d-day daily streak
ach_perfect_title = Flawless
ach_perfect_detail = Win a game with no mistakes
ach_multiplayer_title = Champion
ach_multiplayer_detail = Win your first multiplayer match

# Share
share_result = Share Result
share_result_caption = I matched %d pairs in DoMemory! Can you beat me?

# Onboarding
onboarding_pairs_title = Match the pairs
onboarding_pairs_subtitle = Find every matching pair before time runs out.
onboarding_pace_title = Play at your pace
onboarding_pace_subtitle = Games start at a comfortable pace you can fine-tune anytime from Settings.
onboarding_custom_title = Make it yours
onboarding_custom_subtitle = Create your own memoramas and keep favourites close.
onboarding_skip = Skip
onboarding_continue = Continue
onboarding_get_started = Get started

# Onboarding intro
intro_multiplayer_title = Play with Friends
intro_multiplayer_subtitle = Challenge anyone in real-time multiplayer rooms — just share a 6-digit code or QR.
intro_custom_title = Make It Yours
intro_custom_subtitle = Create your own emoji card sets and play the memoramas you love.
intro_daily_title = Come Back Daily
intro_daily_subtitle = A fresh board every day. Build a streak and keep it alive!
intro_skip = Skip
intro_next = Next
intro_get_started = Get Started

# Notification primer
notification_primer_title = Keep your streak alive
notification_primer_message = Turn on reminders and DoMemory will let you know when:
notification_primer_benefit_streak = Your daily challenge streak is about to end
notification_primer_benefit_inactive = You haven't played in a couple of days
notification_primer_benefit_no_spam = That's it — just a few nudges, never spam
notification_primer_preview_title = Don't break your streak!
notification_primer_preview_message = Your 5-day streak ends tonight. Play today's challenge!
notification_primer_enable = Turn On Reminders
notification_primer_later = Maybe Later

# Notifications
notification_reminder_title = Time to play!
notification_reminder_body = You haven't played DoMemory in a while. Keep your mind sharp!
notification_streak_risk_title = Don't break your streak!
notification_streak_risk_body = Your %d-day streak ends tonight. Play today's challenge to keep it alive! 🔥

# What's New (shell)
whats_new_title = What's New in DoMemory
whats_new_button = Let's Play

# What's New v3.0.0 (retired content, still in the catalog)
whats_new_multiplayer_title = Multiplayer
whats_new_multiplayer_description = Challenge a friend in real-time — create a room, share a 6-digit code or QR scan, and race to find the most matching pairs.
whats_new_reminders_title = Play Reminders
whats_new_reminders_description = Get a nudge if you haven't played in a couple of days so your brain stays sharp.
whats_new_theme_title = Light & Dark Mode
whats_new_theme_description = Choose System, Light, or Dark in Settings to match your style.
whats_new_hint_title = Hint
whats_new_hint_description = Stuck? Pause the game and watch a short ad to reveal one hidden pair of cards.
whats_new_games_title = More Games to Play
whats_new_games_description = Dozens of new emoji card sets across every difficulty — over 130 memoramas to master.

# What's New v4.0.0 (retired content)
whats_new_levels_title = Levels
whats_new_levels_description = A brand-new endless mode. Clear a level to unlock the next — boards keep growing and the clock keeps tightening.
whats_new_stars_title = Star Ratings
whats_new_stars_description = Finish fast and clean to earn up to 3 stars on every level. Replay any level to improve your score.
whats_new_powerups_title = Power-Ups
whats_new_powerups_description = Spend your stars mid-game on extra time, a peek at the board, a frozen clock, or a free matching pair.
whats_new_lives_title = Lives & Mistakes
whats_new_lives_description = You get 4 lives a day, and every level allows only so many wrong matches. Out of either? Watch an ad or spend stars to keep going.

# What's New v4.2.0 (current)
whats_new_seasons_title = Season Levels
whats_new_seasons_description = Play limited-time seasons like Spooky Season — a themed set of levels with their own rewards, running for a few weeks before the next one begins.
whats_new_season_artwork_title = Themed Artwork
whats_new_season_artwork_description = Every season brings its own background and card art to the level map, so a new season always looks the part.
whats_new_tap_to_play_title = Tap to Play
whats_new_tap_to_play_description = The level map now pulses to show you what's next, and every tile responds to your tap.
whats_new_season_progress_title = Season Progress
whats_new_season_progress_description = Track your climb through each season with a live progress bar and countdown — clear every level before time runs out.
```

---

## 20. Constants quick reference

Every tunable number in one place, for cross-checking an implementation.

### Timing

| Constant | Value |
|---|---|
| Splash duration | 1.2 s (0.4 s fade out) |
| Card flip-back delay | 2.0 s (0.5 s animation) |
| Matched-card hide delay | 1.0 s (0.35 s animation) |
| Mistake-loss delay | 0.8 s |
| Per-card bonus window (pie) | 2.0 s |
| Time limit by player's difficulty: easy / medium / hard / very hard | 110 / 60 / 60 / 70 s |
| Level time | `LevelCurve.seconds(n)`, 90 → 35 |
| Rewarded extra time (lose screen) | +30 s |
| Power-up extra time | +15 s |
| Peek duration | 1.5 s |
| Freeze duration | 10 s |
| Forgive minimum clock floor | 15 s |
| Multiplayer reconnect grace | 15 s |

### Economy

| Constant | Value |
|---|---|
| Max daily lives | 4 |
| Stars: 3-star threshold | ≥ 50% time left **and** ≤ 1 mistake |
| Stars: 2-star threshold | ≥ 25% time left |
| Power-up costs (time / peek / freeze / reveal) | 3 / 4 / 5 / 6 ★ |
| Extra life | 10 ★ |
| Forgive mistakes | 8 ★, forgives 3 |
| Skip level | 15 ★ |

### Curve anchors

| Curve | Anchors | Bound |
|---|---|---|
| Pairs | (1,3) (5,4) (10,6) (25,9) (50,12) | cap 12 |
| Seconds | (1,90) (5,85) (10,75) (25,60) (50,45) (80,35) | floor 35 |
| Max failures | (1,4) (5,6) (10,8) (25,11) (50,14) | cap 14 |

### Ads

| Constant | Value |
|---|---|
| Interstitial frequency (easy/medium) | every 3 completed games |
| Interstitial frequency (hard/very hard) | every 2 completed games |
| Minimum game duration for interstitial | 20 s |
| Interstitial suppressed after a rewarded ad | 60 s |
| Minimum gap between full-screen ads | 90 s |
| App-open ad freshness | 4 h |
| Rewarded ad-free day | 24 h, after 2 rewarded ads |

### Other

| Constant | Value |
|---|---|
| Daily Challenge pairs | 6 |
| Emoji pool size | 48 |
| Season minimum distinct emoji | 12 |
| Room code length / alphabet | 6 / `ABCDEFGHJKLMNPQRSTUVWXYZ23456789` |
| Room code generation retries | 12 |
| Level map columns | 4 |
| Endless level map page size | 20 (extends when within 4 of the end) |
| Card-tap analytics sample rate | 20% |
| Streak milestones | 3, 7, 14, 30, 100 |
| Achievement thresholds | wins 10/50/100, streak 7/30 |
| Image disk cache budget | ~64 MB |
| Notification hours | inactivity 19:00, streak-at-risk 20:00 |
| Inactivity reminder tiers | day 2, day 7 |

### Identifiers

| Item | Value |
|---|---|
| iOS bundle id | `com.ezequielbrrt.domemory` |
| App Store id | `1533115091` |
| IAP product id | `com.ezequielbrrt.domemory.removeads` ($0.99, non-consumable) |
| URL scheme | `domemory` |
| Universal-link host | `domemory.app` (association file not deployed) |
| App Group (iOS widget) | `group.com.ezequielbrrt.domemory` |
| Firebase project | `domemory-c9211` |
| Firebase hosting | `https://domemory-c9211.web.app` (season artwork) |
| AdMob app id (iOS) | `ca-app-pub-4297174845441653~4688728438` |

---

## 21. Where to look in the iOS source

If a rule here is ambiguous, these are the files that define it.

```
DoMemory/DoMemory/
  Modules/
    Main/          DoMemoryApp, AppDelegate, ContentView, LaunchScreenView
    Home/          HomeView (difficulty picker), FeatureIntroView (onboarding)
    Menu/          MenuView (981 lines: cards, tabs, grid, create sheet), MenuViewModel, Memorama
    Memorize/      MemorizeView, MemorizeViewModel (the whole game loop, ~900 lines)
                   Model/MemoryGame.swift          <- matching rules, card model
                   MemorizeView/Views/             <- CardView, Cardify, Pie, PowerUpBar
                   MemorizeView/Modals/            <- Pause, Quit, Win, Lose, ShareResultCard
    Levels/        LevelsView, LevelsViewModel, LevelMapView (shared map), OutOfLivesModal, LevelsIntroView
    Seasons/       SeasonLevelsView, SeasonLevelsViewModel, Season+Presentation
    Multiplayer/   MultiplayerService (the whole protocol), MultiplayerModels,
                   MultiplayerRoomView, JoinMultiplayerRoomView, QRCodeView, InviteLink
    Settings/      SettingsView (865 lines), SettingsViewModel, AchievementsView
    SharedModules/ Difficulty, UserManageObject (CoreData), RemoteImage, LivesRow, LoaderView
  Services/
    Levels/        LevelCurve, LevelPowerUp, LevelProgressService, LevelProgressStore,
                   LevelLivesService, StarWalletService, SeededGenerator, EmojiPool, LevelsIntroGate
    Seasons/       Season, SeasonCatalogService, SeasonProgressService, SeasonLevelProgressStore
    DailyChallenge/ DailyChallengeService, DailyChallengeShared (widget-shared)
    Ads/           AdsService (placements, capping, presentation)
    Purchases/     PurchaseService (StoreKit 2)
    Notifications/ NotificationService, NotificationPrimerContent
    Haptics/       HapticsService
    GameStats/     GameStatsService (per board), ProfileStatsService (lifetime + achievements)
    RemoteImages/  RemoteImageService
    WhatsNew/      WhatsNewManager, WhatsNewContent
    ReviewRequest/ AppReviews
  Configuration/   AppConfiguration (analytics enum, palette, fonts, theme), Strings
  SupportingFiles/ UserDefaultsKeys, Color+/Array+/Dictionary+ extensions
  <locale>.lproj/  Localizable.strings, InfoPlist.strings

DoMemory/DoMemoryWidget/   DailyChallengeWidget
DoMemory/DoMemoryTests/    19 test files — start here for exact expected behaviour
firebase/scripts/          gamesToJson.py, upload_games.py, upload_seasons.py, seasons.json, data.json
firebase-database.rules.json, firebase.json
CHANGELOG.md               full feature history, 3.0.0 → 4.2.0, with the reasoning
```

The **tests** and the **CHANGELOG** are the two highest-value reads. The tests pin
exact expected values for the curve, stars, lives, wallet and season validation.
The CHANGELOG explains why each rule exists, including several bugs whose fixes
are now load-bearing behaviour.

---

## 22. Leaderboard (planned)

**Not shipped on either platform.** This is the contract both apps build against.
Delivery and decisions are in `.plans/leaderboard.md`. Expected values are in
`firebase/fixtures/leaderboard-v1.json`, generated by
`scripts/leaderboard/build_fixture.py`.

One shared ranking for iOS and Android, on two boards. There is no server, and
scores are not verified beyond the database rules.

| Board | Path | Score |
|---|---|---|
| Stars | `/leaderboard/v1/stars/$uid` | `levels.lifetimeStars`, which excludes season stars |
| Streak | `/leaderboard/v1/streak/$uid` | Longest Daily Challenge streak, not the current one |

### 22.1 Row

| Field | Type | Meaning |
|---|---|---|
| `s` | Whole number | Score. Never goes down while the row exists |
| `t` | Server timestamp, ms | Time of the last write |
| `a`, `b` | Optional whole numbers, 0–31 | Picked adjective and animal. Both present or both absent |

`$uid` is the anonymous Firebase Auth uid. Rows never contain text, so no name can
be written by a player. Picking a name writes `a` and `b` to both of the player's
rows. Rules allow one write per row every 30 s and cap scores at 30,000 stars and
3,650 streak days. Both caps are provisional, set high enough not to reject real
players, and should be checked against analytics before launch. They may be raised
later without an app release.

Rows and rules are defined in `firebase/firebase-database.rules.json`, and
`firebase/tests/rules.test.mjs` pins them. `/config/leaderboard` holds
`{ ios: { enabled, minVersion }, android: { enabled, minVersion } }`. Treat a missing
or unreadable value as off.

### 22.2 Default names

```
value = FNV-1a 64 of "leaderboard-name-" + uid, UTF-8, with the standard basis
                                               14695981039346656037
a = value % 32
b = (value >> 32) % 32
```

Use unsigned 64-bit arithmetic. Do **not** use `SeededGenerator`, because its
stream differs between platforms (§6.1).

Names are not unique. If `a` or `b` is out of range or only one is present, the
reader falls back to the default name.

### 22.3 Word lists

Both lists are **frozen at 32 entries in this order**. Words may be translated, but
reordering, replacing or adding one renames players.

```
Adjectives: Swift Calm Brave Quiet Bright Clever Gentle Happy
            Kind Lucky Merry Mighty Noble Playful Proud Sunny
            Bold Cheerful Curious Daring Eager Friendly Golden Jolly
            Keen Lively Patient Silver Steady Tiny Wise Witty

Animals:    Otter Panda Heron Fox Owl Koala Dolphin Tiger
            Rabbit Turtle Penguin Falcon Badger Beaver Deer Eagle
            Giraffe Hedgehog Kangaroo Lemur Lion Llama Moose Narwhal
            Parrot Puffin Raccoon Seal Sloth Swan Whale Zebra
```

Each app shows names in the reader's language, from
`localization/leaderboard-names.json`. Each locale has a `format`, an adjective list and
an animal list in this same order. An adjective's forms are masculine, feminine, then
neuter, and a locale may list fewer. An animal's `gender` is `m`, `f` or `n`, and picks
the form, falling back to the first. Fall back to English for any other locale.

### 22.4 Reading

- One read per board with `orderByChild("s").limitToLast(50)`, never a live listener.
- Keep each board's result for 15 minutes.
- Sort by `s` descending, then `t` ascending, then uid ascending. Rows that fail to
  decode are dropped.
- A player's own score comes from local stats. Outside the top 50, show the stars or
  days needed: `lastRowScore - ownScore + 1`, only when the board holds 50 rows.
- Check `/config/leaderboard` on each open. A failed read shows the unavailable state.

### 22.5 Writing

- Show a one-time notice before a player's first score is sent, on the Levels screen
  and on the leaderboard itself, so players who never open the board still see it.
  Nothing is sent until the player accepts, so a player who ignores the notice isn't
  included. Declining sends nothing and works like leaving. Hide the notice and the fourth menu
  tab until `/config/leaderboard` allows them, checking once per launch. The tab shows no
  banner while it's selected.
- Add an existing player on their first finished game or first board open after
  updating, never at launch.
- Before the first write on an install, read the player's own rows once. A reinstall
  can keep the uid while local stats restart at zero, and rules reject a lower score,
  so treat a row's score as the last value sent and show the higher of the two.
- After that, write only when a score is above the last value sent, at most once
  every 10 minutes per board. A failed or skipped write is retried after the next
  finished game. Gameplay never waits for it.
- Leaving deletes both rows and sets a local flag that stops further writes until the
  player rejoins.
- **Android:** `LevelProgressService.recordCompletion` returns before DataStore has
  saved the stars, so read the score after that write completes.

### 22.6 Scoring parity

Star thresholds and the Daily Challenge streak rules match on both platforms. One
difference remains: iOS counts whole seconds and Android counts tenths, so a win
within a second of a threshold can earn iOS a higher rating. For example, finishing a
90 s level at 45.5 s with one mistake earns 3 stars on iOS and 2 on Android. Phase L4
matches iOS by rounding Android's remaining time up before awarding stars. The
`starAwards` fixture cases pin the iOS result.
