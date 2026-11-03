package com.ezequielbrrt.domemory.feature.leaderboard

import androidx.lifecycle.ViewModel
import com.ezequielbrrt.domemory.services.analytics.AnalyticsEvent
import com.ezequielbrrt.domemory.services.leaderboard.LeaderboardBoard
import com.ezequielbrrt.domemory.services.leaderboard.LeaderboardException
import com.ezequielbrrt.domemory.services.leaderboard.LeaderboardNameFormatter
import com.ezequielbrrt.domemory.services.leaderboard.LeaderboardNameWords
import com.ezequielbrrt.domemory.services.leaderboard.LeaderboardRow
import com.ezequielbrrt.domemory.services.leaderboard.LeaderboardService
import com.ezequielbrrt.domemory.services.leaderboard.LeaderboardSnapshot
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

class LeaderboardViewModel(
    private val service: LeaderboardService,
    private val formatter: LeaderboardNameFormatter,
    private val onAnalytics: ((AnalyticsEvent) -> Unit)? = null,
) : ViewModel() {

    sealed interface Content {
        data object Loading : Content
        data class Loaded(val snapshot: LeaderboardSnapshot) : Content
        data object Unavailable : Content
        data object Failed : Content
    }

    data class UiState(
        val board: LeaderboardBoard = LeaderboardBoard.STARS,
        val content: Content = Content.Loading,
        /** Null until the stored answer has been read, so the notice can't flash on screen. */
        val hasAcknowledgedNotice: Boolean? = null,
        val ownName: String = "",
        val isWorking: Boolean = false,
        val nameFailed: Boolean = false,
    ) {
        val isLoaded: Boolean get() = content is Content.Loaded
        val currentWords: LeaderboardNameWords
            get() = (content as? Content.Loaded)?.snapshot?.ownWords ?: LeaderboardNameWords(0, 0)
    }

    private val _state = MutableStateFlow(UiState())
    val state: StateFlow<UiState> = _state.asStateFlow()

    fun name(row: LeaderboardRow): String = formatter.name(row.nameWords)

    suspend fun open() {
        refreshParticipation()
        refreshName()
        service.sync()
        load()
    }

    suspend fun select(board: LeaderboardBoard) {
        if (board == _state.value.board) return
        _state.update { it.copy(board = board) }
        onAnalytics?.invoke(AnalyticsEvent.LeaderboardBoardSelected(board.key))
        load()
    }

    suspend fun dismissNotice() {
        service.acknowledgeNotice()
        _state.update { it.copy(hasAcknowledgedNotice = true) }
        onAnalytics?.invoke(AnalyticsEvent.LeaderboardNoticeDismissed)
    }

    suspend fun load() {
        val requested = _state.value.board
        _state.update { it.copy(content = Content.Loading) }
        val content = try {
            Content.Loaded(service.load(requested))
        } catch (error: CancellationException) {
            throw error
        } catch (_: LeaderboardException.Unavailable) {
            Content.Unavailable
        } catch (_: Exception) {
            Content.Failed
        }
        // A newer tab selection owns the screen now, so this answer is stale.
        if (_state.value.board == requested) _state.update { it.copy(content = content) }
    }

    /** Returns true when the name was saved. */
    suspend fun pickName(adjective: Int, animal: Int): Boolean = working {
        try {
            service.pickName(adjective, animal)
            onAnalytics?.invoke(AnalyticsEvent.LeaderboardNameChanged)
            refreshName()
            load()
            true
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            _state.update { it.copy(nameFailed = true) }
            false
        }
    }

    fun dismissFailure() = _state.update { it.copy(nameFailed = false) }

    private suspend fun refreshParticipation() {
        val acknowledged = service.hasAcknowledgedNotice()
        _state.update { it.copy(hasAcknowledgedNotice = acknowledged) }
    }

    private suspend fun refreshName() {
        val words = service.ownNameWords() ?: return
        _state.update { it.copy(ownName = formatter.name(words)) }
    }

    private suspend fun <T> working(block: suspend () -> T): T {
        _state.update { it.copy(isWorking = true) }
        try {
            return block()
        } finally {
            _state.update { it.copy(isWorking = false) }
        }
    }
}
