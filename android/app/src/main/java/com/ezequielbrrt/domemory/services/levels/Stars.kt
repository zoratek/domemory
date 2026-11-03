package com.ezequielbrrt.domemory.services.levels

import kotlin.math.ceil

/**
 * Star rating for a cleared level (spec 7.2). Awarded on a **win only**.
 *
 * The storage rules that go with this live in the progress store: a level's rating is
 * a high-water mark, and only the *improvement* is credited to the spendable wallet —
 * without that, replaying a cleared level is free money.
 */
object Stars {
    const val MAX = 3
    const val THREE_STAR_TIME_FRACTION = 0.50
    const val THREE_STAR_MAX_FAILURES = 1
    const val TWO_STAR_TIME_FRACTION = 0.25
    private const val TICK_DRIFT_MARGIN = 0.000001

    fun award(timeRemaining: Double, totalTime: Double, failedTries: Int): Int {
        if (totalTime <= 0.0) return 1
        // iOS counts whole seconds, so its clock only drops once a full second has passed. This
        // rounds up to the same value, or a win within a second of a threshold would rate lower
        // here than on iOS and put the two platforms' players on an uneven shared leaderboard
        // (spec 22.6). The small margin absorbs floating-point drift from the 0.1 s tick.
        val fraction = ceil(timeRemaining - TICK_DRIFT_MARGIN) / totalTime
        return when {
            fraction >= THREE_STAR_TIME_FRACTION && failedTries <= THREE_STAR_MAX_FAILURES -> 3
            fraction >= TWO_STAR_TIME_FRACTION -> 2
            else -> 1
        }
    }
}
