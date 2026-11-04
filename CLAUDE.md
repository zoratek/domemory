# CLAUDE.md

This file provides guidance to coding agents working anywhere in this
repository. Each platform has its own file with the detail: read
[`ios/CLAUDE.md`](ios/CLAUDE.md) before touching the iOS app. (`ios/AGENTS.md`
is a symlink to it, so Claude Code and Codex read the same guidance.)

## Project Tracker

The tracker follows this product per platform: iOS is `domemory`, Android is
`domemory-android`. An MCP connection to the tracker is configured in
`.mcp.json` at this repo's root. At the start of a session, call
`list_work_items({ appId: "domemory", status: "active" })` (or
`"domemory-android"` when working under `android/`) to see queued work, and
`update_work_item` to mark an item done once it ships.

## What this repository is

One product — DoMemory, a memory-card (memorama) game — shipped as two native
apps against one backend. Both build `com.ezequielbrrt.domemory` and read the
same Firebase project.

```
ios/        SwiftUI app (live on the App Store), its changelog and plans
android/    Jetpack Compose port (live on Google Play)
firebase/   config, database rules, hosted season art, seed scripts, test fixtures — shared
.plans/     cross-platform plans
localization/ translations shared by both apps
metadata/   store release copy: ios/ by version and locale, android/ Play notes by version
assets/     shared media: brand/ (icon source Domemory.xcf), images/ (store screenshots,
            ads, campaigns), videos/, animations/ (Lottie), proposals/, archive/
scripts/    tooling: animations/, playable/, store-art/, leaderboard/ (test fixture)
```

Both apps have live players, so a Firebase rules change must keep the versions
on both stores working.

iOS is the behavioural source of truth. `android/DOMEMORY_ANDROID_SPEC.md`
describes what the app does in enough detail to build Android without reading
the Swift; `android/ANDROID_PLAN.md` holds the stack and phase decisions. When
the two disagree about behaviour, the spec wins.

## Cross-platform parity

Seven types exist in both languages and **must agree**, because they decide what
a player sees:

| Type | iOS | Android |
|------|-----|---------|
| `LevelCurve` | `ios/DoMemory/DoMemory/Services/Levels/` | `android/…/services/levels/` |
| `LevelProgressStore` | same | same |
| `EmojiPool`, `SeededGenerator` | same | `android/…/core/rng/` |
| `MemoryGame`, `Difficulty` | `…/Modules/Memorize/Model/`, `…/SharedModules/Models/` | `android/…/core/model/` |
| `CardView` | `…/MemorizeView/Views/` | `android/…/feature/game/` |

**`SeededGenerator` does not produce the same numbers on both platforms.** The
iOS FNV offset basis is `1_469_598_103_934_665_603`, one digit short of the
standard `14695981039346656037` that Android uses, so the same seed gives a
different stream. Live iOS boards depend on the existing value, so do not
"correct" either side without a deliberate decision, and don't use this generator
for anything both platforms must compute identically.

**The leaderboard contract is planned and must also agree** once it ships:
`android/DOMEMORY_ANDROID_SPEC.md` §22 defines the row format, ordering, default
names and frozen word lists, and `firebase/fixtures/leaderboard-v1.json` holds
the expected values for both test suites. See `.plans/leaderboard.md`.

`LevelCurve` sets pairs, seconds and `maxFailures` per level; if the two
implementations drift, level 40 is a different game on each platform and nothing
reports it. `EmojiPool` is worse: boards are generated from a seeded RNG, so the
**order** of its 48 emoji is part of the contract. Only ever append, and append
in both languages in the same commit. Both are currently in sync — 48 entries,
identical order.

Change these in one commit covering both platforms. That is the main reason this
repository is a monorepo.

## Firebase (`firebase/`)

Run every `firebase` command **from `firebase/`** — `firebase.json` resolves
`"rules"` and `"public"` relative to itself.

Committing a rules or config change does **not** publish it. Deploy explicitly:

```
firebase deploy --only database   # firebase-database.rules.json
firebase deploy --only hosting    # season art + Cache-Control headers
```

Test rules changes with `npm run test:rules` from `firebase/`, after `npm install`.
It runs the database emulator under a `demo-` project id, so it can't reach
production, and needs Java 21 or later. If the default Java is older, point
`JAVA_HOME` and `PATH` at Android Studio's `Contents/jbr/Contents/Home` for that
command. The tests also pin the paths live apps use.

`firebase/scripts/leaderboard_admin.py` removes fake leaderboard scores and controls
the leaderboard kill switch. It only previews changes unless passed `--apply`.

Season art under `/seasons/**` is served `immutable` with a one-year max-age, so
a published URL is a permanent contract. Replacing a season's artwork means a
**new** path — never overwrite the bytes at an existing URL.

`firebase/scripts/data.json` and `android/app/src/test/resources/data.json` look
different but are not. The first is pretty-printed and wrapped as
`{"data": [...]}` for RTDB import; the second is the same 134 boards, minified
and unwrapped, matching what the app sees under `/data`. They are byte-different
and value-identical — do not "fix" one to match the other. `BoardDecoderTest.kt`
consumes the Android copy.

## App Store release copy

`metadata/ios/<version>/` is the single source of truth: `release-copy.json`
holds `english_approved` and per-locale review status for ten locales
(`en-US`, `es-MX`, `pt-BR`, `fr-FR`, `de-DE`, `it`, `ja`, `ko`, `hi`, `zh-Hans`),
alongside plain-text exports.

There is **no fastlane**. It was removed because its lane called
`upload_to_app_store` with no arguments, so `deliver` uploaded a stale
`fastlane/metadata/` by default and would have silently reverted live store copy.
Builds are archived and uploaded from Xcode, and **the build number is set by
hand** — nothing derives it any more.

Screenshots live in `assets/images/store/screenshots/<device>/<locale>/`
(`iphone`, `ipad`), shared with the Google Play listing by decision (the images
depict the iOS UI, not Android's Compose UI — a deliberate reuse, not an
oversight). `upload-4.4.0.md` beside them records the checksums of the live
sets. The catalog's App Store artwork agent owns export and upload; do not
reintroduce per-app export or upload scripts.

## Repository conventions

**Tags are platform-prefixed** going forward — `ios/4.3.0`, `android/1.0.0`.
Tags `2.1.0` through `4.2.0` predate the monorepo and are all iOS.

**`.gitignore` is split three ways** and the split is deliberate: the root holds
cross-cutting rules, `ios/.gitignore` holds Xcode/Tuist/SPM rules whose patterns
are anchored (`DoMemory/*.xcodeproj` only resolves from `ios/`), and
`android/.gitignore` holds Gradle rules. Add a rule to the file whose directory
it is anchored against, not to the root.

**Some directories are deliberately absent from git.** `ios/marketing/`,
`ios/my-video/` and `ios/artifacts/` exist on the developer's machine and are
ignored, not untracked — marketing sources, a Remotion project and video renders.
Do not add them; migrating them in is a deliberate future decision.

**`android/local.properties` must never be committed** — it holds an absolute
path to a local Android SDK.
