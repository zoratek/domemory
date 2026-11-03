package com.ezequielbrrt.domemory.services.leaderboard

import com.ezequielbrrt.domemory.core.rng.SeededGenerator

/**
 * The pure rules both apps must agree on, because iOS and Android players read and write the
 * same rows (spec 22). `firebase/fixtures/leaderboard-v1.json` pins the expected values, and
 * iOS's `LeaderboardContract.swift` is the counterpart of this file.
 */
enum class LeaderboardBoard(val key: String) {
    STARS("stars"),
    STREAK("streak");

    val path: String get() = "leaderboard/v1/$key"
}

object LeaderboardLimits {
    const val BOARD_SIZE = 50
    const val CACHE_MILLIS = 15 * 60 * 1000L
    const val MINIMUM_WRITE_GAP_MILLIS = 10 * 60 * 1000L
}

data class LeaderboardNameWords(val adjective: Int, val animal: Int)

object LeaderboardNames {
    /** Frozen: translate these, but never reorder, replace or add to them, because that would rename players. */
    val ADJECTIVES = listOf(
        "Swift", "Calm", "Brave", "Quiet", "Bright", "Clever", "Gentle", "Happy",
        "Kind", "Lucky", "Merry", "Mighty", "Noble", "Playful", "Proud", "Sunny",
        "Bold", "Cheerful", "Curious", "Daring", "Eager", "Friendly", "Golden", "Jolly",
        "Keen", "Lively", "Patient", "Silver", "Steady", "Tiny", "Wise", "Witty",
    )

    /** Frozen, like [ADJECTIVES]. */
    val ANIMALS = listOf(
        "Otter", "Panda", "Heron", "Fox", "Owl", "Koala", "Dolphin", "Tiger",
        "Rabbit", "Turtle", "Penguin", "Falcon", "Badger", "Beaver", "Deer", "Eagle",
        "Giraffe", "Hedgehog", "Kangaroo", "Lemur", "Lion", "Llama", "Moose", "Narwhal",
        "Parrot", "Puffin", "Raccoon", "Seal", "Sloth", "Swan", "Whale", "Zebra",
    )

    /**
     * Uses the hash directly, never the generator's stream: iOS's FNV basis is one digit short
     * of the standard value used here, so the two apps' `SeededGenerator` numbers differ, and
     * iOS implements this same standard hash separately for leaderboard names.
     */
    fun defaultWords(uid: String): LeaderboardNameWords {
        val value = SeededGenerator.fnv1a64("leaderboard-name-$uid")
        return LeaderboardNameWords(
            adjective = (value % ADJECTIVES.size.toULong()).toInt(),
            animal = ((value shr 32) % ANIMALS.size.toULong()).toInt(),
        )
    }

    /** The picked words when both are valid, otherwise the default name. */
    fun words(adjective: Int?, animal: Int?, uid: String): LeaderboardNameWords =
        if (adjective != null && animal != null && isValid(adjective, animal)) {
            LeaderboardNameWords(adjective, animal)
        } else {
            defaultWords(uid)
        }

    fun isValid(adjective: Int, animal: Int): Boolean =
        adjective in ADJECTIVES.indices && animal in ANIMALS.indices
}

data class LeaderboardRow(
    val uid: String,
    val score: Int,
    val updatedAt: Long,
    val adjective: Int? = null,
    val animal: Int? = null,
) {
    val nameWords: LeaderboardNameWords get() = LeaderboardNames.words(adjective, animal, uid)

    companion object {
        /** Null for a row without a usable score or timestamp. */
        fun from(uid: String, value: Any?): LeaderboardRow? {
            val fields = value as? Map<*, *> ?: return null
            val score = wholeNumber(fields["s"])?.takeIf { it >= 0 } ?: return null
            val updatedAt = wholeNumber(fields["t"]) ?: return null
            return LeaderboardRow(
                uid = uid,
                score = score.toInt(),
                updatedAt = updatedAt,
                adjective = wholeNumber(fields["a"])?.toInt(),
                animal = wholeNumber(fields["b"])?.toInt(),
            )
        }

        /** Highest score first, then whoever reached it earlier, then uid, so every client shows the same order. */
        fun ranked(rows: List<LeaderboardRow>): List<LeaderboardRow> = rows.sortedWith(
            compareByDescending<LeaderboardRow> { it.score }
                .thenBy { it.updatedAt }
                .thenBy { it.uid },
        )

        fun ranked(payload: Map<String, Any?>): List<LeaderboardRow> =
            ranked(payload.mapNotNull { (uid, value) -> from(uid, value) })

        /** Points needed to pass the last row, or 0 while the board still has room. */
        fun pointsToTopBoard(boardSize: Int, lastRowScore: Int, ownScore: Int): Int =
            if (boardSize < LeaderboardLimits.BOARD_SIZE) 0 else maxOf(0, lastRowScore - ownScore + 1)

        private fun wholeNumber(value: Any?): Long? = when (value) {
            is Int -> value.toLong()
            is Long -> value
            is Double -> value.takeIf { it % 1.0 == 0.0 }?.toLong()
            else -> null
        }
    }
}

/** `/config/leaderboard`. Anything missing or malformed means off. */
data class LeaderboardConfig(val isEnabled: Boolean, val minimumVersion: String) {

    fun allows(appVersion: String): Boolean {
        if (!isEnabled) return false
        val minimum = versionParts(minimumVersion) ?: return false
        val current = versionParts(appVersion) ?: return false
        for (index in minimum.indices) {
            if (current[index] != minimum[index]) return current[index] > minimum[index]
        }
        return true
    }

    companion object {
        fun from(payload: Any?): LeaderboardConfig {
            val platform = (payload as? Map<*, *>)?.get("android") as? Map<*, *>
            return LeaderboardConfig(
                isEnabled = platform?.get("enabled") as? Boolean ?: false,
                minimumVersion = platform?.get("minVersion") as? String ?: "",
            )
        }

        private fun versionParts(version: String): List<Int>? {
            val parts = version.split(".").map { it.toIntOrNull() ?: return null }
            return parts.takeIf { it.size == 3 }
        }
    }
}
