package com.ezequielbrrt.domemory.services.multiplayer

import com.ezequielbrrt.domemory.core.model.Board
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.random.Random

class MultiplayerCardsTest {
    private val items = listOf("🐶", "🐱", "🐭", "🐹", "🐰", "🦊", "🐻", "🐼", "🐨", "🐯", "🦁", "🐮")
    private val board = Board(id = "animals", name = "Animals", items = items)

    @Test fun `double-item cards keep iOS's ids and item ids`() {
        val cards = MultiplayerCards.from(Board(id = "animals", name = "Animals", items = listOf("🐶", "🐱")))

        assertEquals(
            setOf(
                MultiplayerCard(0, 0, "🐶"), MultiplayerCard(1, 0, "🐶"),
                MultiplayerCard(2, 1, "🐱"), MultiplayerCard(3, 1, "🐱"),
            ),
            cards.toSet(),
        )
        assertEquals(4, cards.size)
    }

    @Test fun `adjacency cards keep iOS's ids and item ids`() {
        val cards = MultiplayerCards.from(
            Board(id = "pairs", name = "Pairs", items = listOf("one", "uno", "two", "dos"), isDoubleItem = false),
        )

        assertEquals(
            setOf(
                MultiplayerCard(0, 0, "one"), MultiplayerCard(1, 0, "uno"),
                MultiplayerCard(2, 2, "two"), MultiplayerCard(3, 2, "dos"),
            ),
            cards.toSet(),
        )
    }

    @Test fun `a deal doesn't leave every pair side by side`() {
        // Regression: Android hosts dealt 🐶🐶🐱🐱…, so each card's match was the next card.
        repeat(20) { seed ->
            val cards = MultiplayerCards.from(board, Random(seed))
            val sideBySide = cards.chunked(2).count { (first, second) -> first.itemId == second.itemId }
            assertTrue("Seed $seed left $sideBySide of ${items.size} pairs together", sideBySide < items.size / 2)
        }
    }

    @Test fun `every deal contains each pair exactly twice`() {
        val cards = MultiplayerCards.from(board, Random(7))

        assertEquals(items.size * 2, cards.size)
        assertEquals(cards.size, cards.map { it.id }.toSet().size)
        assertTrue(cards.groupBy { it.itemId }.values.all { it.size == 2 })
    }

    @Test fun `a deal starts face down`() {
        assertTrue(MultiplayerCards.from(board, Random(7)).none { it.isFaceUp || it.isMatched })
    }

    @Test fun `different deals produce different boards`() {
        assertNotEquals(MultiplayerCards.from(board, Random(1)), MultiplayerCards.from(board, Random(2)))
    }

    @Test fun `a rematch turns every card face down in a new order`() {
        val finished = MultiplayerCards.from(board, Random(1)).map { it.copy(isFaceUp = true, isMatched = true) }

        val rematch = MultiplayerCards.redeal(finished, Random(2))

        assertTrue(rematch.none { it.isFaceUp || it.isMatched })
        assertEquals(finished.map { it.id }.toSet(), rematch.map { it.id }.toSet())
        assertNotEquals(finished.map { it.id }, rematch.map { it.id })
    }
}
