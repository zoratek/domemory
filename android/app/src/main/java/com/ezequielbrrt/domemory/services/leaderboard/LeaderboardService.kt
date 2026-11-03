package com.ezequielbrrt.domemory.services.leaderboard

import com.ezequielbrrt.domemory.data.prefs.UserPreferences
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.util.concurrent.ConcurrentHashMap

data class LeaderboardWrite(val board: LeaderboardBoard, val score: Int, val words: LeaderboardNameWords?)

sealed class LeaderboardException : Exception() {
    data object Unavailable : LeaderboardException() { private fun readResolve(): Any = Unavailable }
    data object InvalidName : LeaderboardException() { private fun readResolve(): Any = InvalidName }
}

/** The seam between the leaderboard's rules and Firebase, so the rules can be tested without a database. */
interface LeaderboardBackend {
    suspend fun currentUid(): String
    suspend fun readConfig(): Any?
    suspend fun readTop(board: LeaderboardBoard): Map<String, Any?>
    suspend fun readRow(board: LeaderboardBoard, uid: String): Any?
    suspend fun write(writes: List<LeaderboardWrite>, uid: String)
}

/** What the score ticket says under the player's score. */
sealed interface LeaderboardTicketStatus {
    data class Ranked(val rank: Int) : LeaderboardTicketStatus
    data class PointsToTopBoard(val points: Int) : LeaderboardTicketStatus
    data object NoScore : LeaderboardTicketStatus

    /** The player has a score, but it isn't on this copy of the board yet. */
    data object Pending : LeaderboardTicketStatus
}

data class LeaderboardSnapshot(
    val board: LeaderboardBoard,
    val rows: List<LeaderboardRow>,
    val uid: String,
    val ownScore: Int,
    val ownWords: LeaderboardNameWords,
) {
    val isOwnRowOnBoard: Boolean get() = rows.any { it.uid == uid }
    val ticketStatus: LeaderboardTicketStatus
        get() {
            val index = rows.indexOfFirst { it.uid == uid }
            return when {
                index >= 0 -> LeaderboardTicketStatus.Ranked(index + 1)
                ownScore == 0 -> LeaderboardTicketStatus.NoScore
                pointsToTopBoard > 0 -> LeaderboardTicketStatus.PointsToTopBoard(pointsToTopBoard)
                else -> LeaderboardTicketStatus.Pending
            }
        }
    val pointsToTopBoard: Int
        get() {
            val last = rows.lastOrNull()
            return if (isOwnRowOnBoard || last == null) {
                0
            } else {
                LeaderboardRow.pointsToTopBoard(rows.size, last.score, ownScore)
            }
        }
}

/**
 * Sends the player's scores to the shared leaderboard and reads the top of each board (spec
 * 22), the counterpart of iOS's `LeaderboardService`. Every player with a score is included,
 * and a failure here never affects the game.
 */
class LeaderboardService(
    private val prefs: UserPreferences,
    private val backend: LeaderboardBackend,
    private val appVersion: String,
    private val now: () -> Long = System::currentTimeMillis,
    private val localScore: suspend (LeaderboardBoard) -> Int,
) {
    private data class CachedBoard(val time: Long, val rows: List<LeaderboardRow>)

    private val cache = ConcurrentHashMap<LeaderboardBoard, CachedBoard>()
    private val syncLock = Mutex()

    @Volatile private var cachedAvailability: Boolean? = null

    // -- Participation -------------------------------------------------------------------

    suspend fun hasAcknowledgedNotice(): Boolean = prefs.leaderboardNoticeAcknowledged.first()

    suspend fun acknowledgeNotice() = prefs.setLeaderboardNoticeAcknowledged(true)

    /** Whether the leaderboard is on for this version, checked once per launch. Any failure means no. */
    suspend fun checkAvailability(): Boolean {
        cachedAvailability?.let { return it }
        val available = runCatching { isAvailable() }.getOrDefault(false)
        cachedAvailability = available
        return available
    }

    /** The name the player appears under, once their uid is known. */
    suspend fun ownNameWords(): LeaderboardNameWords? =
        pickedWords() ?: runCatching { LeaderboardNames.defaultWords(backend.currentUid()) }.getOrNull()

    // -- Sending scores ------------------------------------------------------------------

    /** Sends whichever scores are due. Failures are ignored, and a later game tries again. */
    suspend fun sync() {
        syncLock.withLock {
            if (LeaderboardBoard.entries.none { isWriteDue(it) }) return
            runCatching {
                if (!isAvailable()) return
                val uid = backend.currentUid()
                for (board in LeaderboardBoard.entries) {
                    if (!isWriteDue(board)) continue
                    reconcile(board, uid)
                    if (!isWriteDue(board)) continue
                    prefs.setLeaderboardLastAttempt(board.key, now())
                    val score = localScore(board)
                    backend.write(listOf(LeaderboardWrite(board, score, pickedWords())), uid)
                    prefs.setLeaderboardLastSent(board.key, score)
                    cache.remove(board)
                }
            }
        }
    }

    /** Changes the player's name on any rows they have. Without one yet, the pick is sent with their first score. */
    suspend fun pickName(adjective: Int, animal: Int) {
        if (!LeaderboardNames.isValid(adjective, animal)) throw LeaderboardException.InvalidName
        if (!isAvailable()) throw LeaderboardException.Unavailable

        val uid = backend.currentUid()
        val words = LeaderboardNameWords(adjective, animal)
        val writes = LeaderboardBoard.entries.mapNotNull { board ->
            reconcile(board, uid)
            ownScore(board).takeIf { it > 0 }?.let { LeaderboardWrite(board, it, words) }
        }
        if (writes.isNotEmpty()) {
            backend.write(writes, uid)
            writes.forEach {
                prefs.setLeaderboardLastSent(it.board.key, it.score)
                prefs.setLeaderboardLastAttempt(it.board.key, now())
            }
        }
        prefs.setLeaderboardPickedWords(adjective, animal)
        cache.clear()
    }

    // -- Reading -------------------------------------------------------------------------

    /** The top of a board, kept for 15 minutes. Throws [LeaderboardException.Unavailable] while the kill switch is off. */
    suspend fun load(board: LeaderboardBoard): LeaderboardSnapshot {
        if (!isAvailable()) throw LeaderboardException.Unavailable
        val uid = backend.currentUid()

        val cached = cache[board]
        val rows = if (cached != null && now() - cached.time < LeaderboardLimits.CACHE_MILLIS) {
            cached.rows
        } else {
            LeaderboardRow.ranked(backend.readTop(board)).also { cache[board] = CachedBoard(now(), it) }
        }

        reconcile(board, uid)
        return LeaderboardSnapshot(
            board = board,
            rows = rows,
            uid = uid,
            ownScore = ownScore(board),
            ownWords = pickedWords() ?: LeaderboardNames.defaultWords(uid),
        )
    }

    // -- Helpers -------------------------------------------------------------------------

    private suspend fun isAvailable(): Boolean =
        LeaderboardConfig.from(backend.readConfig()).allows(appVersion)

    private suspend fun isWriteDue(board: LeaderboardBoard): Boolean {
        if (localScore(board) <= prefs.leaderboardLastSent(board.key).first()) return false
        val lastAttempt = prefs.leaderboardLastAttempt(board.key).first()
        return now() - lastAttempt >= LeaderboardLimits.MINIMUM_WRITE_GAP_MILLIS
    }

    private suspend fun ownScore(board: LeaderboardBoard): Int =
        maxOf(localScore(board), prefs.leaderboardLastSent(board.key).first())

    private suspend fun pickedWords(): LeaderboardNameWords? {
        val (adjective, animal) = prefs.leaderboardPickedWords.first() ?: return null
        return LeaderboardNameWords(adjective, animal).takeIf { LeaderboardNames.isValid(adjective, animal) }
    }

    /**
     * A reinstall can keep the uid while local stats restart at zero, and rules reject a lower
     * score, so the first read or write on an install starts from any existing row.
     */
    private suspend fun reconcile(board: LeaderboardBoard, uid: String) {
        if (prefs.leaderboardReconciled(board.key).first()) return
        LeaderboardRow.from(uid, backend.readRow(board, uid))?.let { row ->
            prefs.setLeaderboardLastSent(board.key, maxOf(row.score, prefs.leaderboardLastSent(board.key).first()))
            val adjective = row.adjective
            val animal = row.animal
            if (pickedWords() == null && adjective != null && animal != null && LeaderboardNames.isValid(adjective, animal)) {
                prefs.setLeaderboardPickedWords(adjective, animal)
            }
        }
        prefs.setLeaderboardReconciled(board.key, true)
    }
}
