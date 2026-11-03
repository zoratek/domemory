package com.ezequielbrrt.domemory.data.remote

import com.ezequielbrrt.domemory.services.leaderboard.LeaderboardBackend
import com.ezequielbrrt.domemory.services.leaderboard.LeaderboardBoard
import com.ezequielbrrt.domemory.services.leaderboard.LeaderboardLimits
import com.ezequielbrrt.domemory.services.leaderboard.LeaderboardWrite
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.database.FirebaseDatabase
import com.google.firebase.database.ServerValue
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withTimeout

/**
 * One-shot reads and multi-path writes for the leaderboard (spec 22). The time limit matters
 * because a read can wait indefinitely while offline.
 */
class FirebaseLeaderboardBackend(
    private val auth: FirebaseAuth = FirebaseAuth.getInstance(),
    private val database: FirebaseDatabase = FirebaseDatabase.getInstance(),
) : LeaderboardBackend {

    override suspend fun currentUid(): String = withTimeout(TIMEOUT_MILLIS) {
        auth.currentUser?.uid
            ?: auth.signInAnonymously().await().user?.uid
            ?: error("Anonymous sign-in returned no user")
    }

    override suspend fun readConfig(): Any? {
        currentUid()
        return withTimeout(TIMEOUT_MILLIS) {
            database.reference.child(CONFIG_PATH).get().await().value
        }
    }

    override suspend fun readTop(board: LeaderboardBoard): Map<String, Any?> = withTimeout(TIMEOUT_MILLIS) {
        val value = database.reference.child(board.path)
            .orderByChild("s")
            .limitToLast(LeaderboardLimits.BOARD_SIZE)
            .get()
            .await()
            .value as? Map<*, *>
        value.orEmpty().entries.associate { (uid, row) -> uid.toString() to row }
    }

    override suspend fun readRow(board: LeaderboardBoard, uid: String): Any? = withTimeout(TIMEOUT_MILLIS) {
        database.reference.child(board.path).child(uid).get().await().value
    }

    override suspend fun write(writes: List<LeaderboardWrite>, uid: String) {
        val values = writes.associate { write ->
            val row = buildMap<String, Any> {
                put("s", write.score)
                put("t", ServerValue.TIMESTAMP)
                write.words?.let {
                    put("a", it.adjective)
                    put("b", it.animal)
                }
            }
            "${write.board.path}/$uid" to row
        }
        update(values)
    }

    override suspend fun deleteRows(uid: String) {
        update(LeaderboardBoard.entries.associate { "${it.path}/$uid" to null })
    }

    private suspend fun update(values: Map<String, Any?>) = withTimeout(TIMEOUT_MILLIS) {
        database.reference.updateChildren(values).await()
    }

    private companion object {
        const val CONFIG_PATH = "config/leaderboard"
        const val TIMEOUT_MILLIS = 10_000L
    }
}
