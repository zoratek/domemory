#!/usr/bin/env python3
"""Writes firebase/fixtures/leaderboard-v1.json, the leaderboard contract's test data.

Both apps' test suites read the output, so the expected values must not come from
either app. Default names use standard FNV-1a 64 directly, not SeededGenerator, because
the two apps' generators produce different numbers (see section 6.1 of
android/DOMEMORY_ANDROID_SPEC.md). Run this again only when adding fixture cases: the
word lists are frozen by section 22 of that spec.
"""

import json
import math
from pathlib import Path

MASK = (1 << 64) - 1
OUTPUT = Path(__file__).resolve().parents[2] / "firebase" / "fixtures" / "leaderboard-v1.json"

ADJECTIVES = [
    "Swift", "Calm", "Brave", "Quiet", "Bright", "Clever", "Gentle", "Happy",
    "Kind", "Lucky", "Merry", "Mighty", "Noble", "Playful", "Proud", "Sunny",
    "Bold", "Cheerful", "Curious", "Daring", "Eager", "Friendly", "Golden", "Jolly",
    "Keen", "Lively", "Patient", "Silver", "Steady", "Tiny", "Wise", "Witty",
]

ANIMALS = [
    "Otter", "Panda", "Heron", "Fox", "Owl", "Koala", "Dolphin", "Tiger",
    "Rabbit", "Turtle", "Penguin", "Falcon", "Badger", "Beaver", "Deer", "Eagle",
    "Giraffe", "Hedgehog", "Kangaroo", "Lemur", "Lion", "Llama", "Moose", "Narwhal",
    "Parrot", "Puffin", "Raccoon", "Seal", "Sloth", "Swan", "Whale", "Zebra",
]

UIDS = [
    "AAAAAAAAAAAAAAAAAAAAAAAAAAAA",
    "zzzzzzzzzzzzzzzzzzzzzzzzzzzz",
    "k3Vq9XbT2mYcL8sRw1ZpN5dHf7Ga",
    "Qm7tE2uJx0Bn4KvP9aSgC6yWiR3l",
    "9fHs1LdO5rUe8TzXc3MjV7qAbN2k",
    "uG4pY6wKiD0hS2oF8nZtQ1xCeB9m",
]


def fnv1a64(text: str) -> int:
    value = 14695981039346656037
    for byte in text.encode("utf-8"):
        value ^= byte
        value = (value * 1099511628211) & MASK
    return value


def default_name(uid: str) -> dict:
    value = fnv1a64("leaderboard-name-" + uid)
    adjective = value % len(ADJECTIVES)
    animal = (value >> 32) % len(ANIMALS)
    return {
        "uid": uid,
        "a": adjective,
        "b": animal,
        "englishName": f"{ADJECTIVES[adjective]} {ANIMALS[animal]}",
    }


def star_award(total: int, elapsed: float, failed_tries: int) -> dict:
    remaining = total - math.floor(elapsed)
    fraction = remaining / total
    if fraction >= 0.5 and failed_tries <= 1:
        stars = 3
    elif fraction >= 0.25:
        stars = 2
    else:
        stars = 1
    return {"totalSeconds": total, "elapsedSeconds": elapsed, "failedTries": failed_tries, "stars": stars}


def main() -> None:
    # Same reference vectors as android/.../SeededGeneratorTest.kt.
    assert fnv1a64("") == 0xCBF29CE484222325
    assert fnv1a64("a") == 0xAF63DC4C8601EC8C
    assert fnv1a64("foobar") == 0x85944171F73967E8
    assert len(ADJECTIVES) == len(set(ADJECTIVES)) == 32
    assert len(ANIMALS) == len(set(ANIMALS)) == 32

    fixture = {
        "version": 1,
        "adjectives": ADJECTIVES,
        "animals": ANIMALS,
        "defaultNames": [default_name(uid) for uid in UIDS],
        "ordering": {
            "rows": [
                {"uid": "playerB", "s": 120, "t": 2000},
                {"uid": "playerD", "s": 90, "t": 1000},
                {"uid": "playerA", "s": 120, "t": 1000},
                {"uid": "playerC", "s": 120, "t": 1000},
            ],
            "expectedOrder": ["playerA", "playerC", "playerB", "playerD"],
        },
        "starsToTopBoard": [
            {"boardSize": 50, "lastRowScore": 475, "ownScore": 412, "expected": 64},
            {"boardSize": 50, "lastRowScore": 475, "ownScore": 475, "expected": 1},
            {"boardSize": 50, "lastRowScore": 475, "ownScore": 500, "expected": 0},
            {"boardSize": 49, "lastRowScore": 475, "ownScore": 0, "expected": 0},
        ],
        "starAwards": [
            star_award(90, 45.0, 1),
            star_award(90, 45.5, 1),
            star_award(90, 45.5, 2),
            star_award(90, 46.0, 1),
            star_award(60, 45.5, 0),
            star_award(60, 46.0, 0),
        ],
    }

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(fixture, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
