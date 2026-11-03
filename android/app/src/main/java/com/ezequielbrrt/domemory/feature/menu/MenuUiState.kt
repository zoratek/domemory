package com.ezequielbrrt.domemory.feature.menu

import com.ezequielbrrt.domemory.core.model.Board
import com.ezequielbrrt.domemory.core.model.Difficulty
import com.ezequielbrrt.domemory.data.repository.CatalogStatus

/**
 * The three tabs on the real menu (spec 2): `[Levels] [My memoramas] [All]`, in that
 * order — the bar itself "opens on Levels". [LEVELS] is a placeholder tile only in this
 * phase; Phase 3 owns `LevelProgressStore` and the level map.
 *
 * [analyticsKey] is the `tab` value of `menu_tab_selected`, spelled like iOS's `GameTab`
 * raw values — explicit so renaming a constant cannot change the reported value.
 */
enum class MenuTab(val analyticsKey: String) { LEVELS("levels"), MINE("mine"), ALL("all"), LEADERBOARD("leaderboard") }

/** Per-board counters displayed on the catalog cards, matching iOS's stat badges. */
data class BoardStats(
    val played: Int = 0,
    val won: Int = 0,
)

data class MenuUiState(
    val selectedTab: MenuTab = MenuTab.LEVELS,
    /** The player's own setting (spec 4) — filters [allBoards] and seeds the game clock. */
    val difficulty: Difficulty = Difficulty.MEDIUM,
    val catalogStatus: CatalogStatus = CatalogStatus.IDLE,
    /** Catalog boards filtered to [difficulty], favourites sorted to the top (spec 13.4). */
    val allBoards: List<Board> = emptyList(),
    /** Custom boards, ignoring [difficulty] entirely (spec 13.3), favourites-first. */
    val myBoards: List<Board> = emptyList(),
    val favoriteIds: Set<String> = emptySet(),
    val boardStats: Map<String, BoardStats> = emptyMap(),
) {
    fun isFavorite(boardId: String): Boolean = boardId in favoriteIds
}

/** Favourites sort to the top of their tab; stable otherwise (spec 13.4). */
internal fun List<Board>.favoritesFirst(favoriteIds: Set<String>): List<Board> =
    sortedByDescending { it.id in favoriteIds }
