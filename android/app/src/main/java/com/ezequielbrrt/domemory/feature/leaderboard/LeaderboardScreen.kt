package com.ezequielbrrt.domemory.feature.leaderboard

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ezequielbrrt.domemory.R
import com.ezequielbrrt.domemory.services.analytics.AnalyticsEvent
import com.ezequielbrrt.domemory.services.analytics.AnalyticsService
import com.ezequielbrrt.domemory.services.haptics.HapticIntent
import com.ezequielbrrt.domemory.services.haptics.HapticsService
import com.ezequielbrrt.domemory.services.leaderboard.LeaderboardBoard
import com.ezequielbrrt.domemory.services.leaderboard.LeaderboardNameFormatter
import com.ezequielbrrt.domemory.services.leaderboard.LeaderboardNameWords
import com.ezequielbrrt.domemory.services.leaderboard.LeaderboardNames
import com.ezequielbrrt.domemory.services.leaderboard.LeaderboardSnapshot
import com.ezequielbrrt.domemory.ui.theme.LocalPalette
import kotlinx.coroutines.launch

/** Android counterpart of iOS's `LeaderboardView`. No ads appear on this screen, by decision. */
@Composable
fun LeaderboardScreen(
    viewModel: LeaderboardViewModel,
    formatter: LeaderboardNameFormatter,
) {
    val state by viewModel.state.collectAsState()
    val palette = LocalPalette.current
    val scope = rememberCoroutineScope()
    var showNamePicker by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        AnalyticsService.log(AnalyticsEvent.LeaderboardOpened)
        AnalyticsService.log(AnalyticsEvent.ScreenView(screenName = "leaderboard", screenClass = "LeaderboardScreen"))
        viewModel.open()
    }

    Column(
        Modifier
            .fillMaxSize()
            .background(palette.appBackground),
    ) {
        val loaded = (state.content as? LeaderboardViewModel.Content.Loaded)?.snapshot
        LazyColumn(
            Modifier.fillMaxSize().padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            item {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.padding(top = 8.dp)) {
                    if (state.hasAcknowledgedNotice == false) {
                        LeaderboardNoticeCard(
                            name = state.ownName,
                            onDismiss = { scope.launch { viewModel.dismissNotice() } },
                        )
                    }
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        BoardTabs(
                            selected = state.board,
                            onSelect = { board ->
                                HapticsService.fire(HapticIntent.SELECT)
                                scope.launch { viewModel.select(board) }
                            },
                            modifier = Modifier.weight(1f),
                        )
                        val changeNameLabel = stringResource(R.string.leaderboard_change_name)
                        IconButton(
                            onClick = {
                                HapticsService.fire(HapticIntent.TAP)
                                showNamePicker = true
                            },
                            enabled = !state.isWorking && state.isLoaded,
                            modifier = Modifier.semantics { contentDescription = changeNameLabel },
                        ) {
                            Icon(Icons.Filled.Edit, contentDescription = null, tint = palette.primary)
                        }
                    }
                    if (loaded == null) {
                        NotLoadedContent(state.content, onRetry = { scope.launch { viewModel.load() } })
                    } else {
                        OwnSummary(loaded, state.ownName)
                    }
                    if (loaded != null && loaded.rows.isEmpty()) {
                        Message(stringResource(R.string.leaderboard_empty))
                    }
                }
            }
            if (loaded != null) {
                itemsIndexed(loaded.rows, key = { _, row -> row.uid }) { index, row ->
                    BoardRow(
                        rank = index + 1,
                        name = viewModel.name(row),
                        score = row.score,
                        board = loaded.board,
                        isOwn = row.uid == loaded.uid,
                    )
                }
            }
            item { Spacer(Modifier.size(16.dp)) }
        }
    }

    if (showNamePicker) {
        NamePickerDialog(
            formatter = formatter,
            words = state.currentWords,
            onDismiss = { showNamePicker = false },
            onSave = { adjective, animal ->
                scope.launch {
                    if (viewModel.pickName(adjective, animal)) showNamePicker = false
                }
            },
        )
    }

    if (state.nameFailed) {
        AlertDialog(
            onDismissRequest = viewModel::dismissFailure,
            text = { Text(stringResource(R.string.leaderboard_name_failed)) },
            confirmButton = {
                TextButton(onClick = viewModel::dismissFailure) { Text(stringResource(R.string.common_ok)) }
            },
        )
    }
}

@Composable
private fun NotLoadedContent(content: LeaderboardViewModel.Content, onRetry: () -> Unit) {
    val palette = LocalPalette.current
    when (content) {
        LeaderboardViewModel.Content.Unavailable -> Message(stringResource(R.string.leaderboard_unavailable))
        LeaderboardViewModel.Content.Failed -> Column(
            Modifier.fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Message(stringResource(R.string.leaderboard_failed))
            Button(
                onClick = onRetry,
                colors = ButtonDefaults.buttonColors(containerColor = palette.primary),
            ) { Text(stringResource(R.string.leaderboard_retry)) }
        }
        else -> Box(
            Modifier.fillMaxWidth().padding(vertical = 48.dp),
            contentAlignment = Alignment.Center,
        ) { CircularProgressIndicator(color = palette.primary) }
    }
}

@Composable
private fun BoardTabs(selected: LeaderboardBoard, onSelect: (LeaderboardBoard) -> Unit, modifier: Modifier = Modifier) {
    val palette = LocalPalette.current
    Row(
        modifier
            .clip(RoundedCornerShape(12.dp))
            .background(palette.surfaceBorder)
            .padding(3.dp),
    ) {
        LeaderboardBoard.entries.forEach { board ->
            val isSelected = board == selected
            Box(
                Modifier
                    .weight(1f)
                    .heightIn(min = 44.dp)
                    .clip(RoundedCornerShape(9.dp))
                    .background(if (isSelected) palette.surfacePrimary else palette.surfaceBorder)
                    .semantics {
                        role = Role.Tab
                        this.selected = isSelected
                    }
                    .clickable { onSelect(board) },
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    stringResource(
                        if (board == LeaderboardBoard.STARS) R.string.leaderboard_tab_stars else R.string.leaderboard_tab_streak,
                    ),
                    fontSize = 14.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = palette.textPrimary,
                )
            }
        }
    }
}

@Composable
private fun OwnSummary(snapshot: LeaderboardSnapshot, ownName: String) {
    val palette = LocalPalette.current
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(palette.hardAmber.copy(alpha = 0.15f))
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                stringResource(R.string.leaderboard_you_format, ownName),
                fontSize = 15.sp,
                fontWeight = FontWeight.Bold,
                color = palette.textPrimary,
                modifier = Modifier.weight(1f),
            )
            BoardScore(snapshot.ownScore, snapshot.board)
        }
        if (snapshot.pointsToTopBoard > 0) {
            Text(
                stringResource(
                    if (snapshot.board == LeaderboardBoard.STARS) {
                        R.string.leaderboard_points_to_top_stars_format
                    } else {
                        R.string.leaderboard_points_to_top_streak_format
                    },
                    snapshot.pointsToTopBoard,
                ),
                fontSize = 13.sp,
                color = palette.textSecondary,
            )
        }
    }
}

@Composable
private fun BoardRow(rank: Int, name: String, score: Int, board: LeaderboardBoard, isOwn: Boolean) {
    val palette = LocalPalette.current
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(10.dp))
            .background(if (isOwn) palette.hardAmber.copy(alpha = 0.15f) else palette.surfacePrimary)
            .padding(horizontal = 14.dp, vertical = 11.dp)
            .semantics(mergeDescendants = true) {},
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(
            "$rank",
            fontSize = 15.sp,
            fontWeight = FontWeight.ExtraBold,
            color = if (rank <= 3) palette.hardAmber else palette.textSecondary,
            modifier = Modifier.widthIn(min = 28.dp),
        )
        Text(
            name,
            fontSize = 15.sp,
            fontWeight = if (isOwn) FontWeight.Bold else FontWeight.Medium,
            color = palette.textPrimary,
            modifier = Modifier.weight(1f),
        )
        BoardScore(score, board)
    }
}

@Composable
private fun BoardScore(score: Int, board: LeaderboardBoard) {
    val palette = LocalPalette.current
    val label = stringResource(
        if (board == LeaderboardBoard.STARS) R.string.leaderboard_tab_stars else R.string.leaderboard_tab_streak,
    )
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        Icon(
            if (board == LeaderboardBoard.STARS) Icons.Filled.Star else Icons.Filled.LocalFireDepartment,
            contentDescription = label,
            tint = palette.hardAmber,
            modifier = Modifier.size(15.dp),
        )
        Text("$score", fontSize = 15.sp, fontWeight = FontWeight.Bold, color = palette.textPrimary)
    }
}

@Composable
private fun Message(text: String) {
    Text(
        text,
        fontSize = 15.sp,
        color = LocalPalette.current.textSecondary,
        textAlign = TextAlign.Center,
        modifier = Modifier.fillMaxWidth().padding(vertical = 40.dp, horizontal = 8.dp),
    )
}

/** The one-time notice telling a player they're on the public leaderboard. */
@Composable
fun LeaderboardNoticeCard(name: String, onDismiss: () -> Unit, modifier: Modifier = Modifier) {
    val palette = LocalPalette.current
    Column(
        modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(palette.surfacePrimary)
            .border(BorderStroke(1.dp, palette.surfaceBorder), RoundedCornerShape(14.dp))
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text(
            stringResource(R.string.leaderboard_notice_title),
            fontSize = 16.sp,
            fontWeight = FontWeight.Bold,
            color = palette.textPrimary,
        )
        Text(
            stringResource(R.string.leaderboard_notice_body_format, name),
            fontSize = 14.sp,
            color = palette.textSecondary,
        )
        Button(
            onClick = {
                HapticsService.fire(HapticIntent.TAP)
                onDismiss()
            },
            colors = ButtonDefaults.buttonColors(containerColor = palette.primary),
        ) { Text(stringResource(R.string.leaderboard_notice_accept)) }
    }
}

@Composable
private fun NamePickerDialog(
    formatter: LeaderboardNameFormatter,
    words: LeaderboardNameWords,
    onDismiss: () -> Unit,
    onSave: (Int, Int) -> Unit,
) {
    var adjective by remember { mutableIntStateOf(words.adjective) }
    var animal by remember { mutableIntStateOf(words.animal) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.leaderboard_name_title)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(
                    formatter.name(LeaderboardNameWords(adjective, animal)),
                    fontSize = 20.sp,
                    fontWeight = FontWeight.ExtraBold,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth(),
                )
                WordPicker(
                    label = stringResource(R.string.leaderboard_name_adjective),
                    selected = formatter.adjective(adjective, agreeingWith = animal),
                    count = LeaderboardNames.ADJECTIVES.size,
                    option = { formatter.adjective(it, agreeingWith = animal) },
                    onSelect = { adjective = it },
                )
                WordPicker(
                    label = stringResource(R.string.leaderboard_name_animal),
                    selected = formatter.animal(animal),
                    count = LeaderboardNames.ANIMALS.size,
                    option = formatter::animal,
                    onSelect = { animal = it },
                )
            }
        },
        confirmButton = {
            TextButton(onClick = { onSave(adjective, animal) }) { Text(stringResource(R.string.leaderboard_name_save)) }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text(stringResource(R.string.common_cancel)) }
        },
    )
}

@Composable
private fun WordPicker(
    label: String,
    selected: String,
    count: Int,
    option: (Int) -> String,
    onSelect: (Int) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(label, fontSize = 13.sp, color = LocalPalette.current.textSecondary)
        Box {
            OutlinedButton(onClick = { expanded = true }, modifier = Modifier.fillMaxWidth()) {
                Text(selected)
            }
            DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                repeat(count) { index ->
                    DropdownMenuItem(
                        text = { Text(option(index)) },
                        onClick = {
                            onSelect(index)
                            expanded = false
                        },
                    )
                }
            }
        }
    }
}
