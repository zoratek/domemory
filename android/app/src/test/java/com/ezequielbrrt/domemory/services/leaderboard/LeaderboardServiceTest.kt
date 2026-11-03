package com.ezequielbrrt.domemory.services.leaderboard

import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import com.ezequielbrrt.domemory.data.prefs.UserPreferences
import com.ezequielbrrt.domemory.feature.leaderboard.LeaderboardViewModel
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.File

private class FakeBackend : LeaderboardBackend {
    var config: Any? = mapOf("android" to mapOf("enabled" to true, "minVersion" to "1.0.0"))
    val rows = mutableMapOf<LeaderboardBoard, Map<String, Any?>>()
    val writes = mutableListOf<List<LeaderboardWrite>>()
    var failNextWrite = false
    var failWrites = false
    var failTopReads = false
    var configReads = 0
    var topReads = 0
    var rowReads = 0

    override suspend fun currentUid() = "me"

    override suspend fun readConfig(): Any? {
        configReads++
        return config
    }

    override suspend fun readTop(board: LeaderboardBoard): Map<String, Any?> {
        if (failTopReads) error("offline")
        topReads++
        return rows[board].orEmpty()
    }

    override suspend fun readRow(board: LeaderboardBoard, uid: String): Any? {
        rowReads++
        return rows[board]?.get(uid)
    }

    override suspend fun write(writes: List<LeaderboardWrite>, uid: String) {
        if (failNextWrite || failWrites) {
            failNextWrite = false
            error("offline")
        }
        this.writes += writes
    }

}

@OptIn(ExperimentalCoroutinesApi::class)
class LeaderboardServiceTest {
    private val backend = FakeBackend()
    private val scores = mutableMapOf(LeaderboardBoard.STARS to 10, LeaderboardBoard.STREAK to 0)
    private var clock = 1_000_000_000L

    private fun TestScope.service(appVersion: String = "1.3.0"): LeaderboardService {
        val file = File.createTempFile("leaderboard", ".preferences_pb").also { it.delete() }
        val prefs = UserPreferences(PreferenceDataStoreFactory.create(scope = backgroundScope, produceFile = { file }))
        return LeaderboardService(prefs, backend, appVersion, now = { clock }, localScore = { scores.getValue(it) })
    }

    private val sentScores get() = backend.writes.flatten().map { it.score }

    private fun waitOutGap() {
        clock += LeaderboardLimits.MINIMUM_WRITE_GAP_MILLIS
    }

    @Test fun `a score is sent without answering the notice`() = runTest {
        val service = service()
        assertFalse(service.hasAcknowledgedNotice())
        service.sync()
        assertEquals(listOf(10), sentScores)
    }

    @Test fun `a zero score creates no row`() = runTest {
        val service = service()
        service.sync()
        assertEquals(listOf(LeaderboardBoard.STARS), backend.writes.flatten().map { it.board })
    }

    @Test fun `a score is sent once then only when it rises after the gap`() = runTest {
        val service = service()
        service.sync()
        assertEquals(listOf(10), sentScores)

        waitOutGap()
        service.sync()
        assertEquals("An unchanged score isn't sent again", listOf(10), sentScores)

        scores[LeaderboardBoard.STARS] = 11
        clock -= 1
        service.sync()
        assertEquals("Too soon", listOf(10), sentScores)

        clock += 1
        service.sync()
        assertEquals(listOf(10, 11), sentScores)
    }

    @Test fun `a failed write is retried after the gap`() = runTest {
        val service = service()
        backend.failNextWrite = true
        service.sync()
        assertTrue(backend.writes.isEmpty())

        service.sync()
        assertTrue("A retry still waits for the gap", backend.writes.isEmpty())

        waitOutGap()
        service.sync()
        assertEquals(listOf(10), sentScores)
    }

    @Test fun `no network is used when nothing is due`() = runTest {
        val service = service()
        scores[LeaderboardBoard.STARS] = 0
        service.sync()
        assertEquals(0, backend.configReads)
    }

    @Test fun `the kill switch stops writes and reads`() = runTest {
        val service = service()
        backend.config = null
        service.sync()
        assertTrue(backend.writes.isEmpty())
        try {
            service.load(LeaderboardBoard.STARS)
            fail("Expected Unavailable")
        } catch (_: LeaderboardException.Unavailable) {
        }
        assertEquals(0, backend.topReads)
    }

    @Test fun `an older app version stays off`() = runTest {
        backend.config = mapOf("android" to mapOf("enabled" to true, "minVersion" to "1.3.0"))
        val service = service(appVersion = "1.2.0")
        service.sync()
        assertTrue(backend.writes.isEmpty())
    }

    @Test fun `a reinstall starts from the existing row`() = runTest {
        backend.rows[LeaderboardBoard.STARS] = mapOf("me" to mapOf("s" to 500L, "t" to 1L, "a" to 3L, "b" to 4L))
        val service = service()

        service.sync()
        assertTrue("A lower score would be rejected", backend.writes.isEmpty())

        val snapshot = service.load(LeaderboardBoard.STARS)
        assertEquals(500, snapshot.ownScore)
        assertEquals(LeaderboardNameWords(3, 4), snapshot.ownWords)

        scores[LeaderboardBoard.STARS] = 501
        service.sync()
        assertEquals(
            listOf(LeaderboardWrite(LeaderboardBoard.STARS, 501, LeaderboardNameWords(3, 4))),
            backend.writes.last(),
        )
    }

    @Test fun `opening a board after a reinstall shows the existing score`() = runTest {
        backend.rows[LeaderboardBoard.STARS] = mapOf("me" to mapOf("s" to 500L, "t" to 1L))
        scores[LeaderboardBoard.STARS] = 0
        assertEquals(500, service().load(LeaderboardBoard.STARS).ownScore)
    }

    @Test fun `the own row is read once per board`() = runTest {
        val service = service()
        service.sync()
        scores[LeaderboardBoard.STARS] = 11
        waitOutGap()
        service.sync()
        assertEquals(1, backend.rowReads)
    }

    @Test fun `picking a name updates rows that have a score`() = runTest {
        scores[LeaderboardBoard.STREAK] = 2
        val service = service()
        service.pickName(1, 2)
        val words = LeaderboardNameWords(1, 2)
        assertEquals(
            listOf(
                listOf(
                    LeaderboardWrite(LeaderboardBoard.STARS, 10, words),
                    LeaderboardWrite(LeaderboardBoard.STREAK, 2, words),
                ),
            ),
            backend.writes,
        )
        assertEquals(words, service.load(LeaderboardBoard.STREAK).ownWords)
    }

    @Test fun `a pick without a score is sent with the first score`() = runTest {
        scores[LeaderboardBoard.STARS] = 0
        val service = service()
        service.pickName(1, 2)
        assertTrue(backend.writes.isEmpty())

        scores[LeaderboardBoard.STARS] = 3
        service.sync()
        assertEquals(LeaderboardNameWords(1, 2), backend.writes.last().first().words)
    }

    @Test fun `an invalid pick is refused`() = runTest {
        val service = service()
        try {
            service.pickName(32, 0)
            fail("Expected InvalidName")
        } catch (_: LeaderboardException.InvalidName) {
        }
        assertTrue(backend.writes.isEmpty())
    }

    @Test fun `a board is cached for 15 minutes`() = runTest {
        backend.rows[LeaderboardBoard.STARS] = mapOf("a" to mapOf("s" to 5L, "t" to 1L))
        val service = service()
        service.load(LeaderboardBoard.STARS)
        service.load(LeaderboardBoard.STARS)
        assertEquals(1, backend.topReads)
        assertEquals("The kill switch is checked on each open", 2, backend.configReads)

        clock += LeaderboardLimits.CACHE_MILLIS
        service.load(LeaderboardBoard.STARS)
        assertEquals(2, backend.topReads)
    }

    @Test fun `the ticket shows the right status`() {
        fun snapshot(rows: List<LeaderboardRow>, ownScore: Int) =
            LeaderboardSnapshot(LeaderboardBoard.STARS, rows, "me", ownScore, LeaderboardNameWords(0, 0))
        val others = (0 until 50).map { LeaderboardRow("p$it", 100 - it, 1L) }
        val onBoard = listOf(LeaderboardRow("a", 9, 1L), LeaderboardRow("me", 5, 1L))

        assertEquals(LeaderboardTicketStatus.Ranked(2), snapshot(onBoard, 5).ticketStatus)
        assertEquals(LeaderboardTicketStatus.PointsToTopBoard(12), snapshot(others, 40).ticketStatus)
        assertEquals(LeaderboardTicketStatus.NoScore, snapshot(others, 0).ticketStatus)
        assertEquals(LeaderboardTicketStatus.NoScore, snapshot(emptyList(), 0).ticketStatus)
        assertEquals(LeaderboardTicketStatus.Pending, snapshot(emptyList(), 5).ticketStatus)
        assertEquals(LeaderboardTicketStatus.Pending, snapshot(others, 90).ticketStatus)
    }

    @Test fun `a snapshot reports the distance to the board`() = runTest {
        backend.rows[LeaderboardBoard.STARS] = (0 until 50).associate { "player$it" to mapOf("s" to 100L + it, "t" to 1L) }
        val snapshot = service().load(LeaderboardBoard.STARS)
        assertFalse(snapshot.isOwnRowOnBoard)
        assertEquals(149, snapshot.rows.first().score)
        assertEquals(91, snapshot.pointsToTopBoard)
    }

    @Test fun `availability is checked once per launch and fails closed`() = runTest {
        val service = service()
        assertTrue(service.checkAvailability())
        assertTrue(service.checkAvailability())
        assertEquals(1, backend.configReads)

        backend.config = mapOf("android" to mapOf("enabled" to false, "minVersion" to "1.0.0"))
        assertFalse(service(appVersion = "1.3.0").checkAvailability())
    }

    // -- View model --------------------------------------------------------------------

    private fun TestScope.viewModel() = LeaderboardViewModel(service(), LeaderboardNameFormatter(null))

    @Test fun `opening sends the score and loads the board`() = runTest {
        backend.rows[LeaderboardBoard.STARS] = mapOf("a" to mapOf("s" to 5L, "t" to 1L))
        val viewModel = viewModel()
        viewModel.open()
        assertEquals(listOf(10), sentScores)
        val content = viewModel.state.value.content as LeaderboardViewModel.Content.Loaded
        assertEquals(listOf("a"), content.snapshot.rows.map { it.uid })
    }

    @Test fun `dismissing the notice remembers it`() = runTest {
        val service = service()
        val viewModel = LeaderboardViewModel(service, LeaderboardNameFormatter(null))
        viewModel.open()
        assertEquals(false, viewModel.state.value.hasAcknowledgedNotice)
        viewModel.dismissNotice()
        assertEquals(true, viewModel.state.value.hasAcknowledgedNotice)
        assertTrue(service.hasAcknowledgedNotice())
    }

    @Test fun `the kill switch shows the unavailable state`() = runTest {
        backend.config = null
        val viewModel = viewModel()
        viewModel.open()
        assertEquals(LeaderboardViewModel.Content.Unavailable, viewModel.state.value.content)
    }

    @Test fun `a failed read shows the retry state and recovers`() = runTest {
        backend.failTopReads = true
        val viewModel = viewModel()
        viewModel.load()
        assertEquals(LeaderboardViewModel.Content.Failed, viewModel.state.value.content)

        backend.failTopReads = false
        viewModel.load()
        assertTrue(viewModel.state.value.isLoaded)
    }

    @Test fun `picking a name refreshes the name`() = runTest {
        val viewModel = viewModel()
        assertTrue(viewModel.pickName(0, 0))
        assertEquals("Swift Otter", viewModel.state.value.ownName)
    }

    @Test fun `a failed pick reports it`() = runTest {
        val viewModel = viewModel()
        backend.failWrites = true
        assertFalse(viewModel.pickName(0, 0))
        assertTrue(viewModel.state.value.nameFailed)
    }
}
