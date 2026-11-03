# Leaderboard

One ranking shared by iOS and Android players, on the existing Firebase project, with
no server and no live connections. It replaces Quick Match for now because of cost.

The contract is in `android/DOMEMORY_ANDROID_SPEC.md` §22.

## Decisions (2026-11-03)

| Question | Decision |
|---|---|
| Joining | Every player with a score is included automatically, with no way to decline or leave (changed 2026-11-03). A one-time notice tells them their name and scores are public. Removal requests go through the admin script |
| Names | Generated, and changeable only by picking from the word lists |
| Scores | Lifetime stars and longest Daily Challenge streak |
| Board size | Top 50, cached for 15 minutes |
| Firebase plan | Spark |
| Entry point | A fourth menu tab on both platforms, with no banner while it's showing. It replaced a Levels header button that was hard to find and tap |
| Fake scores | The owner removes them with an admin script. No report button |

## Phases

| Phase | Scope | Needs | Status |
|---|---|---|---|
| L0 | Contract, fixtures and docs | None | Merged (#122) |
| L1 | Rules, emulator harness, config and admin script | L0 | Merged (#122), rules deployed 2026-11-03 |
| L2 | iOS service | L1 deployed | Merged (#123) |
| L3 | iOS screen, switched off by config | L2 | Merged (#126), translations need review |
| L4 | Android service and screen | L1 deployed | Merged, not yet fully tested on a device |
| L5 | Cross-platform test. The v1 format is frozen when it passes | L3, L4 | Not started |
| L6 | Release iOS 4.6.0 and Android 1.3.0 | L5 | Not started |
| L7 | Review downloads, connections, leavers and cheating after two weeks | L6 | Not started |

L2 and L4 add the fixture tests, because `LeaderboardNames` doesn't exist in either app
until then. L4 also rounds Android's remaining time up before awarding stars (§22.6).

## Firebase deploys

The owner runs these from `firebase/` with `--project domemory-c9211`.

1. **Before L1 merges:** run `firebase database:get /.settings/rules` and compare with
   the repo, because a deploy overwrites whatever is live.
2. **After L1 merges:** run `firebase deploy --only database`, then publish the kill
   switch with both platforms off:
   `python3 scripts/leaderboard_admin.py --credentials KEY.json config --all-off --apply`
3. **After L5:** deploy any fixes. After this, v1 rules may only loosen.
4. **When both releases are live:** check Spark's peak connections, then turn on both
   platforms together.

## Spark limits

Automatic joining means every player can send scores, and Spark rejects new connections
above 100 at once, shared with the catalog, seasons and multiplayer. Going over a limit
can turn the database off for the whole app. If peak connections are above about 50
before launch, move to Blaze with a budget alert first.

## Before launch

Check the provisional score caps (30,000 stars, 3,650 streak days) against analytics.
This hasn't been done, because analytics isn't reachable from the repo.

## Out of scope

Quick Match, Cloud Functions, accounts, exact rank outside the top 50, Daily Challenge
speed, weekly boards, friends lists, typed names, and ads on the leaderboard screen.

## Findings outside this plan

- `SeededGenerator` differs between platforms (§6.1). Nothing here depends on it.
- Android hosts may deal unshuffled friend-room boards, and brief network drops may
  become forfeits. Neither has been confirmed on a device.
