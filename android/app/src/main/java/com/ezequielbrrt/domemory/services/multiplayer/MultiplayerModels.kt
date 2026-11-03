package com.ezequielbrrt.domemory.services.multiplayer

import com.ezequielbrrt.domemory.core.model.Board
import com.ezequielbrrt.domemory.core.model.Card
import kotlin.random.Random

/** Wire-compatible room values from spec 10.2 and iOS's MultiplayerModels.swift. */
enum class MultiplayerRoomStatus { WAITING, READY, PLAYING, RECONNECTING, FINISHED, ABANDONED }
enum class MultiplayerGameSource { FIREBASE, CUSTOM }

data class MultiplayerPlayer(
    val id: String,
    val name: String,
    val connected: Boolean = true,
    val lastSeenAt: Long,
    val score: Int = 0,
    // Spec 10.2/10.4: per-player mutual ready-check flag, false until explicitly set true.
    // Reset to false on both players whenever the host (re)picks a game — see
    // MultiplayerService.selectGame.
    val isReady: Boolean = false,
)

data class MultiplayerCustomGamePayload(
    val title: String,
    val category: String,
    val items: List<String>,
    val itemType: String,
    val isDoubleItem: Boolean,
) {
    fun asBoard(id: String, difficulty: String?) = Board(
        id = id, name = title, category = category, difficulty = difficulty,
        items = items, itemType = itemType, isDoubleItem = isDoubleItem,
    )

    companion object {
        fun from(board: Board) = MultiplayerCustomGamePayload(
            title = board.name, category = board.category, items = board.items,
            itemType = board.itemType, isDoubleItem = board.isDoubleItem,
        )
    }
}

/** A room card intentionally only has the persistent fields of [Card]. */
data class MultiplayerCard(
    val id: Int,
    val itemId: Int,
    val content: String,
    val isFaceUp: Boolean = false,
    val isMatched: Boolean = false,
) {
    fun asCard() = Card(id, itemId, content, isFaceUp, isMatched)
    companion object { fun from(card: Card) = MultiplayerCard(card.id, card.itemId, card.content, card.isFaceUp, card.isMatched) }
}

/**
 * Deals a room's cards, the counterpart of iOS's `makeCards`. Only the host calls this. It writes
 * the shuffled list into the room once, and both players render that list, so they always see the
 * same board. Clients must never reorder the cards they read from a room.
 */
object MultiplayerCards {
    fun from(board: Board, random: Random = Random.Default): List<MultiplayerCard> {
        val cards = if (board.isDoubleItem) {
            board.items.flatMapIndexed { itemId, content ->
                listOf(
                    MultiplayerCard(id = itemId * 2, itemId = itemId, content = content),
                    MultiplayerCard(id = itemId * 2 + 1, itemId = itemId, content = content),
                )
            }
        } else {
            board.items.mapIndexed { index, content ->
                MultiplayerCard(id = index, itemId = if (index % 2 == 0) index else index - 1, content = content)
            }
        }
        return cards.shuffled(random)
    }

    /** The same cards face down in a new order, for a rematch. */
    fun redeal(cards: List<MultiplayerCard>, random: Random = Random.Default): List<MultiplayerCard> =
        cards.map { it.copy(isFaceUp = false, isMatched = false) }.shuffled(random)
}

data class MultiplayerRoom(
    val id: String,
    val code: String,
    val status: MultiplayerRoomStatus,
    val createdAt: Long,
    val updatedAt: Long,
    val hostId: String,
    val guestId: String? = null,
    val players: Map<String, MultiplayerPlayer>,
    val gameSource: MultiplayerGameSource,
    val gameId: String,
    val gameName: String,
    val difficulty: String? = null,
    val customGamePayload: MultiplayerCustomGamePayload? = null,
    val currentPlayerId: String? = null,
    val cards: List<MultiplayerCard> = emptyList(),
    val selectedCardIds: List<Int> = emptyList(),
    val winnerId: String? = null,
    val disconnectStartedAt: Long? = null,
    val disconnectPlayerId: String? = null,
) {
    val allPairsMatched get() = cards.isNotEmpty() && cards.all { it.isMatched }
    fun isTurnFor(playerId: String) = status == MultiplayerRoomStatus.PLAYING && currentPlayerId == playerId

    /** Spec 10.2: `gameId == ""` is the wire sentinel for "no game chosen yet" — a room only
     * ever has an empty [gameId] in WAITING/READY, never once [status] reaches PLAYING. */
    val hasSelectedGame get() = gameId.isNotEmpty()

    /**
     * Spec 10.4 step 5: the pure precondition for the automatic, host-only start —
     * `status == ready`, a game picked, exactly two players present, and every player ready.
     * Deliberately doesn't check `hostId == caller` — that half of the guard belongs to
     * whoever is *acting* (see [MultiplayerService.start]'s transaction and
     * `MultiplayerViewModel`'s auto-start trigger), not to the room's own data.
     */
    val readyToAutoStart get() =
        status == MultiplayerRoomStatus.READY &&
            hasSelectedGame &&
            players.size == 2 &&
            players.values.all { it.isReady }

    /**
     * Whether tapping a card right now would actually flip one — mirrors iOS's
     * `MultiplayerRoomViewModel.isInteractionEnabled`. Checked locally (no round trip to
     * Firebase) so the optimistic `CARD_FLIP` haptic a tap fires immediately — before the
     * transaction that actually moves the card even lands — matches what a legal tap would
     * do: it's this player's turn, the room is still playing, and no already-selected pair
     * is sitting there waiting to clear. Takes an `isCurrentUser` predicate rather than a raw
     * id, the same shape [isTurnFor] would need if it also had to resolve "me" from the
     * caller's auth session rather than being handed an id directly.
     */
    fun canFlipNow(isCurrentUser: (String) -> Boolean): Boolean =
        status == MultiplayerRoomStatus.PLAYING &&
            currentPlayerId?.let(isCurrentUser) == true &&
            selectedCardIds.size < 2
}
