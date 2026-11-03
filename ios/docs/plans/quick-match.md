# Quick Match — online multiplayer against other players

> **Parked on 2026-11-03** because of multiplayer costs. `.plans/leaderboard.md` is
> the current work. A 2 November review also found this plan can't be built as
> written: quick rooms can't use `joinRoom`, and the ticket lifecycle can strand
> players. Review it again before reopening.

Play a live match against a random online opponent, with no friend, room code or
invite needed. This sits beside the existing friend rooms (create, share code,
join) and does not replace them.

## Requested outcome

Today every multiplayer match needs two people who already know each other: one
creates a room and the other types or scans its 6-character code. Quick Match adds
a single **"Find opponent"** action. The app puts the player in a matchmaking
queue, pairs them with whoever else is searching, picks a catalog board, and
starts the match. Neither player picks a game, readies up or shares anything.

## Evidence observed

Read from the code, not assumed:

- **The room model already fits an opponent you don't know.** Create, join, the
  ready check, the host-side auto-start, turns, presence, the 15 s reconnect grace
  and the winner rules all work on `/multiplayerRooms/{roomId}` and don't care how
  the second player arrived (`MultiplayerService.swift:56–501`, spec §10.4–10.5).
  Quick Match can be **a new way to fill a room**, not a new game engine.
- **Auto-start is already condition-driven.** The host's client deals the cards as
  soon as `status == ready`, `gameId` is non-empty, there are two players and both
  `isReady` (`MultiplayerRoomViewModel.swift:396`, `triggerAutoStartIfBothReady`).
  If a quick room is created with the game already chosen and each player writes
  `isReady: true` on entry, the match starts with no new start logic.
- **iOS moves use read-then-write; Android uses transactions.** iOS `chooseCard`,
  `clearUnmatchedSelection` and `hideMatchedFaceUpCards` do `getCodable` and then
  `updateChildValues` (`MultiplayerService.swift:346–446`). Android runs all of
  them through `runTransaction` (`MultiplayerService.kt:201`, `RoomTransactionPlan.kt`).
  Friend rooms rarely write at the same time. A turn timer (below) adds a second
  writer during the opponent's turn, so iOS needs transactions too.
- **Writes are trusted to the client.** The rules let either player write anything
  in their room (`firebase/firebase-database.rules.json`). Card contents for
  face-down cards sit in `cards[].content`, readable by both players. This is fine
  between friends but becomes a cheating surface with strangers.
- **There is no backend code.** `firebase/` holds rules, hosting and seed scripts,
  with no Cloud Functions. Server-side matchmaking or move validation would need
  the Blaze plan and a new `functions/` deploy target.
- **Player names are fixed placeholders.** `Strings.multiplayerHostName` and
  `multiplayerGuestName` (`MultiplayerService.swift:65, 205`). Nothing is typed by
  the user, so there is no free-text content to moderate today.
- **Custom memoramas travel inside the room** as `customGamePayload`. That is
  user-generated content, and sending it to a stranger needs moderation.
- **Mixed versions must decode.** `MultiplayerRoom.init(from:)` requires `code`,
  `gameId`, `gameName`, `difficulty` and `gameSource`. New fields must be optional
  with defaults, the same way `isReady` was added (`MultiplayerModels.swift:30–41`).
- **Difficulty has four cases**: `easy`, `medium`, `hard`, `veryHard`.
- Wins go to `profile.multiplayerWins` and the "Champion" achievement
  (`ProfileStatsService.swift:62`). These are local, with no server leaderboard.

## Design

### Matchmaking: one waiting ticket per bucket, claimed by transaction

```
/matchmaking/v1/{bucket}  ->  { uid, roomId, createdAt } | null
```

A single node per bucket holds **at most one** waiting player. "Find opponent"
runs one RTDB transaction on that node:

- **Empty or stale** (older than 45 s): create a quick room in `waiting` with
  the board already chosen, write my ticket `{uid, roomId, createdAt}`, set
  `onDisconnect().removeValue()` on it, and observe my room. When someone joins,
  the room goes `ready`, both are ready, and the existing auto-start deals.
- **Holds someone else's fresh ticket**: set the node to `null` (claim it) and
  join `roomId` through the existing `joinRoom` path with `isReady: true`.
- **Holds my own ticket**: keep waiting (this is a retry or a reconnect).

A single-node transaction is atomic, so two searchers can never claim the same
ticket. This needs no server and suits low player counts. A claimed room the host
has already left fails `joinRoom` with `roomUnavailable`. The client then re-runs
the search, at most twice, before showing an error.

**`v1` is a protocol version.** Clients with different quick-room formats never
meet: bumping it moves new clients to a fresh queue, and old clients keep matching
each other.

**Buckets.** Launch with **one bucket** (`any`) so matches happen as often as
possible. Split by difficulty only when analytics show long waits are not the
problem. The bucket key is the only thing that changes when you split.

### Quick room = an ordinary room plus three optional fields

```
kind: "friend" | "quick"        // absent → "friend"
turnStartedAt: epoch seconds    // quick only
timeoutStrikes: { <uid>: Int }  // quick only
```

- `code` stays required by old decoders, so quick rooms get a code too. It is
  never shown and never written to `/multiplayerRoomCodes`, so nobody can join a
  quick room by typing it.
- The board is chosen at room creation: a random catalog board from `/data` that
  fits the bucket. **Never a custom memorama.**
- Both players' `isReady` is `true` from the moment they enter, so there is no
  ready step and auto-start fires as soon as the guest joins.

### Turn timer (quick rooms only)

A friend will wait for you; a stranger may just walk away. When a player has the
turn and makes no move for **20 s**, the *opponent's* client may pass the turn.
That write is a transaction guarded on `turnStartedAt` being unchanged, and it
increments the idle player's `timeoutStrikes`. **3 strikes forfeits the match.**
The board shows a countdown ring on the active player during the last 10 s.
Disconnects keep the existing 15 s grace, which is a separate mechanism.

### Identity without user-generated content

Each player's `name` is generated from fixed lists: a localized adjective plus an
animal ("Brave Otter"), seeded by uid, together with an emoji avatar from
`EmojiPool`. There is no free text and no chat. This keeps the feature outside
App Store Guideline 1.2 (report/block for UGC). If preset emotes are added later,
they must also come from a fixed set.

### End of match

- **"New opponent"** goes straight back to searching. This is the primary action.
- **"Rematch"** is a request, not the host-only immediate redeal friend rooms
  use. Each player sets `isReady` again, and the host redeals once both have.
  If the other player leaves, the button changes to "Opponent left".
- Leaving during `playing` counts as a forfeit, as today.

### Kill switch

`/config/quickMatch: { enabled, minAppVersion }` is read the same way `/seasons`
is. When it is disabled, the entry point is hidden. This lets you turn the feature
off without an app release if the queue misbehaves or gets abused.

### Cheating: what v1 accepts

A modified client could read face-down card contents or write a fake score. v1
**accepts that risk**, because it has no leaderboard, no rating and no reward for
winning beyond a local stat. v1 also adds `.validate` rules on quick rooms:

- a score may only go up by 1 per write;
- `winnerId` must be one of the two players or null;
- `cards[].itemId` and `cards[].content` are immutable once dealt;
- writes come only from the two players.

Fully preventing cheating needs Cloud Functions (hidden faces in a server-only
node, revealed by a callable, with authoritative turns). That decision belongs to
any future **ranked** mode, not to v1.

## Assumptions

- "Other players, not the local one" means **remote strangers via matchmaking**.
  Friend-code rooms already exist.
- Two players per match, the same rules as friend rooms.
- iOS ships first. Android implements the same wire format from the updated spec.
  Because the queue is cross-platform, an iOS player can be matched with an
  Android player.

## Non-goals

- Ranked play, ELO, global leaderboards, friends lists, chat.
- More than two players.
- Custom memoramas in Quick Match.
- Bots dressed up as human players (see Q2).
- Push notifications such as "someone is looking for a match".

## Success criteria

- Two devices that tap "Find opponent" within 45 s of each other land in the same
  match without typing anything, and the board deals automatically.
- An iOS device and an Android device can be matched with each other.
- Cancelling a search removes the ticket. Killing the app removes it through
  `onDisconnect`. A stale ticket is never matched.
- An idle player loses the turn after 20 s and forfeits after 3 strikes.
- Friend rooms behave exactly as before, verified by the existing tests and a
  manual friend-room match.
- A pre-Quick-Match client still decodes every room and never enters the `v1` queue.
- Analytics answer "how long do people wait, and how many give up?":
  `quick_match_search_started`, `quick_match_found` (`wait_seconds`),
  `quick_match_cancelled` (`wait_seconds`), `quick_match_turn_timeout`,
  and `multiplayer_game_finished` with a new `result: forfeit`.

## Question ledger

| # | Question | Recommendation | Why it matters |
|---|----------|----------------|----------------|
| Q1 | Client-only matchmaking or Cloud Functions? | **Client-only for v1.** | Functions need the Blaze plan and a new deploy target. The transaction design is correct without them, and server-side validation only pays off once there is ranked play. |
| Q2 | What happens when nobody else is searching? | After 30 s, offer **"Keep waiting"**, **"Invite a friend"** (existing room flow) and **"Play solo"**. A **clearly labelled** CPU opponent can follow later. | With low player counts, an empty queue is the main product risk. A bot passed off as a person would mislead players. |
| Q3 | Should iOS ship before the Android release? | **Yes**, and test the format cross-platform before the Android release. | Android is unreleased. The matchmaking node and room fields are just data; Android only has to implement them. |
| Q4 | One bucket or one per difficulty at launch? | **One** (`any`), using `medium` boards. | Splitting the queue four ways makes waits longer. Revisit once wait-time data exists. |
| Q5 | Do Quick Match wins count toward `multiplayerWins` / Champion? | **Yes.** | Players would expect any multiplayer win to count. |

## Open design points for spec §10.8

The release-planning review (2026-10-20) raised these. Settle them in the spec
before any Phase 1 code:

- **Per-platform gating.** iOS (4.x) and Android (1.x) are versioned separately,
  so `/config/quickMatch` needs `minAppVersion: { ios, android }` or a per-platform
  `enabled`. That keeps Android hidden until 1.1.0.
- **Server time for the turn timer.** The opponent's clock decides the timeout,
  so client epoch seconds would pass turns early or late on skewed devices. Write
  `turnStartedAt` with `ServerValue.timestamp()`, and compare against
  `.info/serverTimeOffset`.
- **Who writes the name.** Each player writes their own generated name when
  entering the room.
- **Kill-switch freshness.** Decide how stale a cached `/config` read may be
  before the entry point hides.
- **App Review.** Keep Quick Match enabled during review and put the Q2 fallback
  in the review notes. Hiding it risks Guideline 2.3.1.
- **Play forms.** Android 1.1.0 must also update the content rating and the Data
  safety form.
- **Ads.** Decide whether the multiplayer-finished native ad and the interstitial
  cadence apply to quick rooms.

## Tracking

- Feature #226: iOS 4.6.0 (phases 1–3), Android 1.1.0 (phase 4).
- Chore #227: the backend (rules, `/config`, cleanup), deployed before 4.6.0 is
  submitted.

## Phases

### Phase 1 — Spec and wire format (no UI)

- Add §10.8 "Quick Match" to `android/DOMEMORY_ANDROID_SPEC.md` covering the
  ticket node, the new room fields, the timer and the rules. The spec wins on
  behaviour, so it changes first.
- iOS: add `kind`, `turnStartedAt` and `timeoutStrikes` to `MultiplayerRoom` as
  optional fields with defaults. Add decoding tests for rooms without them.
- iOS: move `chooseCard`, `clearUnmatchedSelection` and `hideMatchedFaceUpCards`
  onto `runTransactionBlock`, matching Android. Friend rooms benefit too.
- Rules: add `matchmaking/$version/$bucket` (auth users only; a write must either
  set `uid == auth.uid` or clear the node), `.validate` rules for quick rooms, and
  a read-only `config`. Keep the room rules' `.read` and `.write` exceptions
  symmetric: the claimer's `joinRoom` reads the quick room before writing to it,
  and `ios/CLAUDE.md` records the outage that an asymmetric rule caused in 3.0.0.
  **Deploy with `firebase deploy --only database` from `firebase/`**, because
  committing the rules does not publish them.

**Exit:** existing friend-room tests pass, a manual friend match works, and the
rules are deployed and checked in the emulator.

### Phase 2 — iOS matchmaking and searching screen

- `QuickMatchService`: search, cancel, claim, retry on a dead room, ticket
  `onDisconnect`, and board picking from the cached catalog.
- A "Find opponent" entry in the menu's multiplayer menu, next to Create and Join.
- Searching screen: animated cards, elapsed time and Cancel, plus the 30 s
  fallback options from Q2.
- Generated names and avatars; strings in all ten `Localizable.strings` files.
- Analytics events and the `/config/quickMatch` kill switch.

**Exit:** two simulators match each other, cancel and app-kill both clean up the
ticket, and the kill switch hides the entry.

### Phase 3 — Stranger-safe match rules

- The turn timer, countdown ring, strikes and forfeit, for quick rooms only.
- An end screen with "New opponent" and rematch-by-request.
- Haptics and accessibility announcements for "Opponent found", the timer
  warning and the forfeit.

**Exit:** idle-turn and forfeit paths verified on two devices, and friend rooms
unchanged.

### Phase 4 — Android parity

Implement §10.8 in `services/multiplayer/` and `feature/multiplayer/`, reusing
`RoomTransactionPlan` and `MultiplayerTurnReducer`. Add tests for the ticket
transaction and the timer reducer.

**Exit:** an Android device matches with an iOS device through the queue in a live
test, not just a passing unit test (same standard as Phase 6 of `ANDROID_PLAN.md`).

### Phase 5 — Release

- What's New entry, release copy in `metadata/ios/<version>/`, and new screenshots
  if the menu changes.
- Re-answer the App Store age-rating questionnaire (multiplayer with no chat).
- Watch the wait-time and cancel analytics. Use them to decide on difficulty
  buckets and the CPU fallback.

## Risks

| Risk | Mitigation |
|------|-----------|
| Too few players online, so searches time out | One bucket, the Q2 fallbacks, wait-time analytics; a labelled CPU opponent is the next step. |
| Queue vandalism (anyone signed in can clear a ticket) | Rules restrict ticket writes to "my uid" or null. The client retries. The kill switch exists. |
| Abandoned rooms build up in RTDB | Quick rooms are small. A periodic cleanup script in `firebase/scripts/` deletes `finished`/`abandoned` rooms older than 24 h. A scheduled Function can replace it if Q1 changes. |
| A modified client cheats | Accepted for v1 (no stakes) and limited by `.validate` rules. Server authority is a prerequisite for any ranked mode. |
| iOS and Android disagree on quick-room fields | Spec first (Phase 1), a versioned queue key, and a live cross-platform exit criterion. |
