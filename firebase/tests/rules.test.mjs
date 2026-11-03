// Database rules tests. Run from firebase/ with `npm run test:rules`.
//
// The demo- project id keeps the emulator from ever reaching production.

import { readFileSync } from "node:fs";
import { after, before, beforeEach, describe, test } from "node:test";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  get,
  limitToFirst,
  limitToLast,
  orderByChild,
  query,
  ref,
  remove,
  serverTimestamp,
  set,
  update,
} from "firebase/database";

const STARS = "leaderboard/v1/stars";
const STREAK = "leaderboard/v1/streak";
const LONG_AGO = 1_000;

let env;
const alice = () => env.authenticatedContext("alice").database();
const bob = () => env.authenticatedContext("bob").database();
const signedOut = () => env.unauthenticatedContext().database();
const row = (s, extra = {}) => ({ s, t: serverTimestamp(), ...extra });

async function seed(path, value) {
  await env.withSecurityRulesDisabled((context) => set(ref(context.database(), path), value));
}

before(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-domemory",
    database: { rules: readFileSync("firebase-database.rules.json", "utf8") },
  });
});

after(() => env.cleanup());
beforeEach(() => env.clearDatabase());

for (const [board, path, cap] of [["stars", STARS, 30000], ["streak", STREAK, 3650]]) {
  describe(`${board} board writes`, () => {
    test("a player can create their own row", () =>
      assertSucceeds(set(ref(alice(), `${path}/alice`), row(120))));

    test("a score at the cap is accepted", () =>
      assertSucceeds(set(ref(alice(), `${path}/alice`), row(cap))));

    test("a player can't write another player's row", () =>
      assertFails(set(ref(alice(), `${path}/bob`), row(120))));

    test("a signed-out client can't write", () =>
      assertFails(set(ref(signedOut(), `${path}/alice`), row(120))));

    test("a score above the cap is rejected", () =>
      assertFails(set(ref(alice(), `${path}/alice`), row(cap + 1))));

    test("negative, fractional and text scores are rejected", async () => {
      await assertFails(set(ref(alice(), `${path}/alice`), row(-1)));
      await assertFails(set(ref(alice(), `${path}/alice`), row(1.5)));
      await assertFails(set(ref(alice(), `${path}/alice`), row("120")));
    });

    test("a client-chosen timestamp is rejected", () =>
      assertFails(set(ref(alice(), `${path}/alice`), { s: 120, t: 4_102_444_800_000 })));

    test("a row needs both a score and a timestamp", async () => {
      await assertFails(set(ref(alice(), `${path}/alice`), { s: 120 }));
      await assertFails(set(ref(alice(), `${path}/alice`), { t: serverTimestamp() }));
    });

    test("unknown fields, including typed names, are rejected", () =>
      assertFails(set(ref(alice(), `${path}/alice`), row(120, { name: "anything" }))));

    test("a score can rise after the wait", async () => {
      await seed(`${path}/alice`, { s: 100, t: LONG_AGO });
      await assertSucceeds(set(ref(alice(), `${path}/alice`), row(101)));
    });

    test("a score can't drop", async () => {
      await seed(`${path}/alice`, { s: 100, t: LONG_AGO });
      await assertFails(set(ref(alice(), `${path}/alice`), row(99)));
    });

    test("a second write within 30 seconds is rejected", async () => {
      await assertSucceeds(set(ref(alice(), `${path}/alice`), row(100)));
      await assertFails(set(ref(alice(), `${path}/alice`), row(101)));
    });

    test("a picked name is two whole numbers from 0 to 31", async () => {
      await assertSucceeds(set(ref(alice(), `${path}/alice`), row(1, { a: 0, b: 31 })));
      await assertFails(set(ref(bob(), `${path}/bob`), row(1, { a: 32, b: 0 })));
      await assertFails(set(ref(bob(), `${path}/bob`), row(1, { a: -1, b: 0 })));
      await assertFails(set(ref(bob(), `${path}/bob`), row(1, { a: 1.5, b: 0 })));
      await assertFails(set(ref(bob(), `${path}/bob`), row(1, { a: "Swift", b: 0 })));
    });

    test("a picked name needs both words", async () => {
      await assertFails(set(ref(alice(), `${path}/alice`), row(1, { a: 3 })));
      await assertFails(set(ref(alice(), `${path}/alice`), row(1, { b: 3 })));
    });

    test("a player can leave immediately, and rejoin with any valid score", async () => {
      await assertSucceeds(set(ref(alice(), `${path}/alice`), row(100)));
      await assertSucceeds(remove(ref(alice(), `${path}/alice`)));
      await assertSucceeds(set(ref(alice(), `${path}/alice`), row(5)));
    });

    test("a player can't delete another player's row", async () => {
      await seed(`${path}/bob`, { s: 100, t: LONG_AGO });
      await assertFails(remove(ref(alice(), `${path}/bob`)));
    });

    test("a blocked player can't write, but can still delete their row", async () => {
      await seed("leaderboard/v1/blocked/alice", true);
      await seed(`${path}/alice`, { s: 100, t: LONG_AGO });
      await assertFails(set(ref(alice(), `${path}/alice`), row(101)));
      await assertSucceeds(remove(ref(alice(), `${path}/alice`)));
    });
  });

  describe(`${board} board reads`, () => {
    beforeEach(() => seed(`${path}/bob`, { s: 100, t: LONG_AGO }));

    test("the top 50 can be read", () =>
      assertSucceeds(get(query(ref(alice(), path), orderByChild("s"), limitToLast(50)))));

    test("more than 50 rows can't be requested", () =>
      assertFails(get(query(ref(alice(), path), orderByChild("s"), limitToLast(51)))));

    test("the whole board can't be read", () => assertFails(get(ref(alice(), path))));

    test("a limit without score ordering is rejected", () =>
      assertFails(get(query(ref(alice(), path), limitToLast(50)))));

    test("reading from the bottom of the board is rejected", () =>
      assertFails(get(query(ref(alice(), path), orderByChild("s"), limitToFirst(50)))));

    test("a signed-out client can't read the board", () =>
      assertFails(get(query(ref(signedOut(), path), orderByChild("s"), limitToLast(50)))));

    test("a player can read their own row only", async () => {
      await seed(`${path}/alice`, { s: 1, t: LONG_AGO });
      await assertSucceeds(get(ref(alice(), `${path}/alice`)));
      await assertFails(get(ref(alice(), `${path}/bob`)));
    });
  });
}

describe("leaderboard admin paths", () => {
  test("clients can't read or change the block list", async () => {
    await assertFails(get(ref(alice(), "leaderboard/v1/blocked")));
    await assertFails(set(ref(alice(), "leaderboard/v1/blocked/bob"), true));
    await assertFails(remove(ref(alice(), "leaderboard/v1/blocked/alice")));
  });

  test("signed-in clients can read the kill switch and nobody can change it", async () => {
    await assertSucceeds(get(ref(alice(), "config/leaderboard")));
    await assertFails(get(ref(signedOut(), "config/leaderboard")));
    await assertFails(set(ref(alice(), "config/leaderboard/ios/enabled"), true));
  });

  test("nothing else under config or leaderboard is open", async () => {
    await assertFails(get(ref(alice(), "config")));
    await assertFails(get(ref(alice(), "leaderboard")));
    await assertFails(set(ref(alice(), "leaderboard/v2/stars/alice"), row(1)));
    await assertFails(set(ref(alice(), "config/other"), true));
  });

  test("a player can update both of their rows in one write", () =>
    assertSucceeds(
      update(ref(alice()), {
        [`${STARS}/alice`]: row(10, { a: 1, b: 2 }),
        [`${STREAK}/alice`]: row(3, { a: 1, b: 2 }),
      }),
    ));
});

// These pin what the live apps rely on, so a leaderboard rule can't break them.
describe("paths used by live apps", () => {
  test("the board catalog and seasons are public and read-only", async () => {
    await assertSucceeds(get(ref(signedOut(), "data")));
    await assertSucceeds(get(ref(signedOut(), "seasons")));
    await assertFails(set(ref(alice(), "data/0"), {}));
    await assertFails(set(ref(alice(), "seasons/x"), {}));
  });

  test("a host can create a room and a guest can check and join it", async () => {
    await assertSucceeds(set(ref(alice(), "multiplayerRooms/r1"), { hostId: "alice" }));
    await assertSucceeds(get(ref(bob(), "multiplayerRooms/r1")));
    await assertSucceeds(
      set(ref(bob(), "multiplayerRooms/r1"), { hostId: "alice", guestId: "bob" }),
    );
  });

  test("a third player can't read or take a full room", async () => {
    await seed("multiplayerRooms/r1", { hostId: "alice", guestId: "bob" });
    const carol = env.authenticatedContext("carol").database();
    await assertFails(get(ref(carol, "multiplayerRooms/r1")));
    await assertFails(set(ref(carol, "multiplayerRooms/r1"), { hostId: "carol" }));
  });

  test("signed-in players can use room codes", async () => {
    await assertSucceeds(set(ref(alice(), "multiplayerRoomCodes/ABC123"), "r1"));
    await assertSucceeds(get(ref(bob(), "multiplayerRoomCodes/ABC123")));
    await assertFails(get(ref(signedOut(), "multiplayerRoomCodes/ABC123")));
  });
});
