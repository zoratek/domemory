package com.ezequielbrrt.domemory.services.multiplayer

import com.ezequielbrrt.domemory.core.model.Board
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.database.FirebaseDatabase
import com.google.firebase.database.ValueEventListener
import com.google.firebase.database.Transaction
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.suspendCancellableCoroutine
import java.time.Instant
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/** Firebase adapter for the spec 10 room protocol. All move rules live in [MultiplayerTurnReducer]. */
class MultiplayerService(
    private val auth: FirebaseAuth = FirebaseAuth.getInstance(),
    private val database: FirebaseDatabase = FirebaseDatabase.getInstance(),
    private val now: () -> Long = { Instant.now().epochSecond },
) {
    /**
     * Spec 10.4 step 1: host-first — the room is created *empty*, with no game chosen
     * (`gameId`/`gameName`/`difficulty` all `""`, `gameSource: firebase` and ignored until a
     * game is picked via [selectGame]). Takes no board.
     */
    suspend fun createRoom(): MultiplayerRoom {
        val uid = uid()
        val roomId = database.reference.child(ROOMS).push().key ?: error("Could not allocate room")
        val code = reserveCode(roomId)
        val timestamp = now()
        val room = MultiplayerRoom(roomId, code, MultiplayerRoomStatus.WAITING, timestamp, timestamp, uid, players = mapOf(uid to MultiplayerPlayer(uid, "Host", lastSeenAt = timestamp)), gameSource = MultiplayerGameSource.FIREBASE, gameId = "", gameName = "", difficulty = "")
        try {
            database.reference.child(ROOMS).child(roomId).setValue(MultiplayerRoomCodec.encode(room)).await()
        } catch (error: Throwable) {
            database.reference.child(CODES).child(code).removeValue()
            throw error
        }
        configurePresence(roomId, uid)
        return room
    }

    /**
     * Spec 10.4 step 3: host-only, any `waiting`/`ready` room. Sets the game fields from
     * [board] and does **not** touch `status`/`cards`/`currentPlayerId`/scores — no cards are
     * dealt. Resets every current player's `isReady` back to `false`, since readiness was for
     * whatever game (if any) was picked before.
     */
    suspend fun selectGame(roomId: String, board: Board) {
        val uid = uid()
        transaction(roomId) { room ->
            if (room.hostId != uid || room.status !in setOf(MultiplayerRoomStatus.WAITING, MultiplayerRoomStatus.READY)) return@transaction null
            room.copy(
                gameSource = if (board.isCustom) MultiplayerGameSource.CUSTOM else MultiplayerGameSource.FIREBASE,
                gameId = board.id,
                gameName = board.name,
                difficulty = board.difficulty,
                customGamePayload = board.takeIf { it.isCustom }?.let(MultiplayerCustomGamePayload::from),
                players = room.players.mapValues { it.value.copy(isReady = false) },
                updatedAt = now(),
            )
        }
    }

    /** Spec 10.4 step 4: either current player (host or guest) marks their own readiness.
     * Never starts the match by itself — see [readyToAutoStart's][MultiplayerRoom] use in
     * [start]'s guard and `MultiplayerViewModel`'s auto-start trigger. */
    suspend fun setReady(roomId: String, ready: Boolean) {
        val uid = uid()
        transaction(roomId) { room ->
            val player = room.players[uid] ?: return@transaction null
            room.copy(players = room.players + (uid to player.copy(isReady = ready)), updatedAt = now())
        }
    }

    suspend fun joinRoom(rawCode: String): String {
        val uid = uid(); val code = RoomCode.normalize(rawCode) ?: throw MultiplayerException.InvalidCode
        val roomId = database.reference.child(CODES).child(code).get().await().getValue(String::class.java) ?: throw MultiplayerException.NotFound
        transaction(roomId) { room ->
            when {
                room.status !in setOf(MultiplayerRoomStatus.WAITING, MultiplayerRoomStatus.READY, MultiplayerRoomStatus.PLAYING, MultiplayerRoomStatus.RECONNECTING) -> null
                room.hostId == uid || room.guestId == uid -> {
                    val player = room.players[uid] ?: return@transaction null
                    room.copy(players = room.players + (uid to player.copy(connected = true, lastSeenAt = now())), updatedAt = now())
                }
                room.guestId != null -> null
                else -> {
                    val time = now()
                    val guest = MultiplayerPlayer(uid, "Guest", lastSeenAt = time)
                    room.copy(
                        guestId = uid,
                        status = MultiplayerRoomStatus.READY,
                        updatedAt = time,
                        players = room.players + (uid to guest),
                    )
                }
            }
        }
        configurePresence(roomId, uid); return roomId
    }

    fun observe(roomId: String): Flow<Result<MultiplayerRoom>> = callbackFlow {
        val ref = database.reference.child(ROOMS).child(roomId)
        val listener = object : ValueEventListener {
            override fun onDataChange(snapshot: com.google.firebase.database.DataSnapshot) { trySend(MultiplayerRoomCodec.decode(snapshot.value)?.let(Result.Companion::success) ?: Result.failure(MultiplayerException.NotFound)) }
            override fun onCancelled(error: com.google.firebase.database.DatabaseError) { trySend(Result.failure(error.toException())) }
        }
        ref.addValueEventListener(listener); awaitClose { ref.removeEventListener(listener) }
    }

    /**
     * Spec 10.4 step 5: reactive, host-only — the caller (`MultiplayerViewModel`'s auto-start
     * trigger) is expected to call this only once [MultiplayerRoom.readyToAutoStart] is true.
     * The transaction still re-checks it against the newest room, since Firebase may re-run
     * this transform against a snapshot that raced the one the caller observed.
     */
    suspend fun start(roomId: String, board: Board) {
        val uid = uid()
        transaction(roomId) { room ->
            if (room.hostId != uid || !room.readyToAutoStart) return@transaction null
            room.copy(
                status = MultiplayerRoomStatus.PLAYING,
                currentPlayerId = room.hostId,
                // The host deals once and writes the order into the room, so both players see
                // the same shuffled board. Board.buildCards() isn't used because its ids differ
                // from the ones iOS's `makeCards` writes.
                cards = MultiplayerCards.from(board),
                selectedCardIds = emptyList(),
                winnerId = null,
                players = room.players.mapValues { it.value.copy(score = 0) },
                updatedAt = now(),
            )
        }
    }
    suspend fun restart(roomId: String) {
        val uid = uid()
        transaction(roomId) { room ->
            if (room.hostId != uid || room.status != MultiplayerRoomStatus.FINISHED) return@transaction null
            room.copy(
                status = MultiplayerRoomStatus.PLAYING,
                currentPlayerId = room.hostId,
                cards = MultiplayerCards.redeal(room.cards),
                selectedCardIds = emptyList(),
                winnerId = null,
                players = room.players.mapValues { it.value.copy(score = 0) },
                disconnectStartedAt = null,
                disconnectPlayerId = null,
                updatedAt = now(),
            )
        }
    }
    suspend fun choose(roomId: String, cardId: Int) {
        val uid = uid()
        transaction(roomId) { current ->
            (MultiplayerTurnReducer.choose(current, uid, cardId, now()) as? MultiplayerTurnReducer.Result.Applied)?.room
        }
    }
    suspend fun clearMismatch(roomId: String, ids: List<Int>) { transaction(roomId) { MultiplayerTurnReducer.clearMismatch(it, ids, now()) } }
    /** Reconciles Firebase onDisconnect presence with the shared 15-second grace period. */
    suspend fun reconcilePresence(roomId: String) {
        transaction(roomId) { room ->
            if (room.status !in setOf(MultiplayerRoomStatus.PLAYING, MultiplayerRoomStatus.RECONNECTING)) return@transaction room
            val disconnected = room.players.values.firstOrNull { !it.connected }
            when {
                disconnected == null && room.status == MultiplayerRoomStatus.RECONNECTING -> room.copy(
                    status = MultiplayerRoomStatus.PLAYING,
                    disconnectStartedAt = null,
                    disconnectPlayerId = null,
                    updatedAt = now(),
                )
                disconnected == null -> room
                room.disconnectStartedAt == null -> room.copy(
                    status = MultiplayerRoomStatus.RECONNECTING,
                    disconnectStartedAt = now(),
                    disconnectPlayerId = disconnected.id,
                    updatedAt = now(),
                )
                now() - room.disconnectStartedAt >= RECONNECT_GRACE_SECONDS -> room.copy(
                    status = MultiplayerRoomStatus.FINISHED,
                    winnerId = room.players.keys.firstOrNull { it != disconnected.id },
                    updatedAt = now(),
                )
                else -> room
            }
        }
    }
    suspend fun leave(roomId: String) {
        val uid = uid()
        transaction(roomId) { room ->
            val player = room.players[uid] ?: return@transaction null
            val status = if (room.status in setOf(MultiplayerRoomStatus.WAITING, MultiplayerRoomStatus.READY)) MultiplayerRoomStatus.ABANDONED else room.status
            room.copy(status = status, players = room.players + (uid to player.copy(connected = false, lastSeenAt = now())), updatedAt = now())
        }
    }

    fun isCurrentUser(userId: String) = auth.currentUser?.uid == userId

    private suspend fun uid(): String = auth.currentUser?.uid ?: auth.signInAnonymously().await().user?.uid ?: throw MultiplayerException.Authentication
    /** Firebase re-runs [transform] with the newest room if another player writes first. */
    private suspend fun transaction(id: String, transform: (MultiplayerRoom) -> MultiplayerRoom?) = suspendCancellableCoroutine<Unit> { continuation ->
        database.reference.child(ROOMS).child(id).runTransaction(object : Transaction.Handler {
            override fun doTransaction(data: com.google.firebase.database.MutableData): Transaction.Result {
                return when (val plan = RoomTransactionPlan.of(data.value, transform)) {
                    RoomTransactionPlan.AwaitServer -> Transaction.success(data)
                    RoomTransactionPlan.Abort -> Transaction.abort()
                    is RoomTransactionPlan.Commit -> {
                        data.value = MultiplayerRoomCodec.encode(plan.room)
                        Transaction.success(data)
                    }
                }
            }
            override fun onComplete(error: com.google.firebase.database.DatabaseError?, committed: Boolean, snapshot: com.google.firebase.database.DataSnapshot?) {
                if (!continuation.isActive) return
                when {
                    error != null -> continuation.resumeWithException(error.toException())
                    !committed -> continuation.resumeWithException(MultiplayerException.InvalidMove)
                    // An AwaitServer pass commits nothing: if the server has no room either, it was deleted.
                    snapshot?.value == null -> continuation.resumeWithException(MultiplayerException.NotFound)
                    else -> continuation.resume(Unit)
                }
            }
        })
    }
    private fun room(value: Any?) = MultiplayerRoomCodec.decode(value) ?: throw MultiplayerException.Decoding
    private fun configurePresence(id: String, uid: String) { val ref = database.reference.child(ROOMS).child(id).child("players").child(uid); ref.child("connected").onDisconnect().setValue(false); ref.child("lastSeenAt").onDisconnect().setValue(now()) }
    private suspend fun reserveCode(roomId: String): String {
        repeat(12) {
            val code = RoomCode.generate()
            val reserved = suspendCancellableCoroutine<Boolean> { continuation ->
                database.reference.child(CODES).child(code).runTransaction(object : Transaction.Handler {
                    override fun doTransaction(data: com.google.firebase.database.MutableData): Transaction.Result {
                        if (data.value != null) return Transaction.abort()
                        data.value = roomId
                        return Transaction.success(data)
                    }
                    override fun onComplete(error: com.google.firebase.database.DatabaseError?, committed: Boolean, snapshot: com.google.firebase.database.DataSnapshot?) {
                        if (!continuation.isActive) return
                        if (error != null) continuation.resumeWithException(error.toException()) else continuation.resume(committed)
                    }
                })
            }
            if (reserved) return code
        }
        throw MultiplayerException.Unavailable
    }
    companion object {
        const val RECONNECT_GRACE_SECONDS = 15L
        private const val ROOMS = "multiplayerRooms"
        private const val CODES = "multiplayerRoomCodes"
    }
}

sealed class MultiplayerException : Exception() { data object Authentication : MultiplayerException(); data object NotFound : MultiplayerException(); data object Full : MultiplayerException(); data object Unavailable : MultiplayerException(); data object InvalidMove : MultiplayerException(); data object InvalidCode : MultiplayerException(); data object Decoding : MultiplayerException() }
