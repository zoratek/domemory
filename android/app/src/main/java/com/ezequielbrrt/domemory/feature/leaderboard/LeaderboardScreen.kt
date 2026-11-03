package com.ezequielbrrt.domemory.feature.leaderboard

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
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
import androidx.compose.material3.HorizontalDivider
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
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
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
import com.ezequielbrrt.domemory.services.leaderboard.LeaderboardTicketStatus
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
        LazyColumn(Modifier.fillMaxSize().padding(horizontal = 16.dp)) {
            item {
                Column(
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                    modifier = Modifier.padding(top = 8.dp, bottom = 12.dp),
                ) {
                    if (state.hasAcknowledgedNotice == false) {
                        LeaderboardNoticeCard(
                            name = state.ownName,
                            onDismiss = { scope.launch { viewModel.dismissNotice() } },
                        )
                    }
                    BoardTabs(
                        selected = state.board,
                        onSelect = { board ->
                            HapticsService.fire(HapticIntent.SELECT)
                            scope.launch { viewModel.select(board) }
                        },
                        modifier = Modifier.fillMaxWidth(),
                    )
                    if (loaded == null) {
                        NotLoadedContent(state.content, onRetry = { scope.launch { viewModel.load() } })
                    } else {
                        Text(
                            stringResource(
                                if (loaded.board == LeaderboardBoard.STARS) {
                                    R.string.leaderboard_caption_stars
                                } else {
                                    R.string.leaderboard_caption_streak
                                },
                            ),
                            fontSize = 13.sp,
                            color = palette.textSecondary,
                        )
                        LeaderboardTicket(
                            snapshot = loaded,
                            name = state.ownName,
                            canChangeName = !state.isWorking,
                            onChangeName = {
                                HapticsService.fire(HapticIntent.TAP)
                                showNamePicker = true
                            },
                        )
                        if (loaded.rows.isEmpty()) {
                            Message(stringResource(R.string.leaderboard_empty))
                        } else {
                            Text(
                                stringResource(R.string.leaderboard_top_50),
                                fontSize = 15.sp,
                                fontWeight = FontWeight.Bold,
                                color = palette.textPrimary,
                                modifier = Modifier.semantics { heading() },
                            )
                        }
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
                        isFirst = index == 0,
                        isLast = index == loaded.rows.lastIndex,
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

/** The player's own score, the most personal thing on the screen. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun LeaderboardTicket(
    snapshot: LeaderboardSnapshot,
    name: String,
    canChangeName: Boolean,
    onChangeName: () -> Unit,
) {
    val palette = LocalPalette.current
    val isStars = snapshot.board == LeaderboardBoard.STARS
    val status = when (val current = snapshot.ticketStatus) {
        is LeaderboardTicketStatus.Ranked -> stringResource(R.string.leaderboard_rank_format, current.rank)
        is LeaderboardTicketStatus.PointsToTopBoard -> stringResource(
            if (isStars) R.string.leaderboard_points_to_top_stars_format else R.string.leaderboard_points_to_top_streak_format,
            current.points,
        )
        LeaderboardTicketStatus.NoScore -> stringResource(
            if (isStars) R.string.leaderboard_zero_stars else R.string.leaderboard_zero_streak,
        )
        LeaderboardTicketStatus.Pending -> stringResource(R.string.leaderboard_pending)
    }
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(20.dp))
            .background(palette.surfacePrimary)
            .border(BorderStroke(2.dp, palette.primary), RoundedCornerShape(20.dp))
            .padding(start = 16.dp, end = 16.dp, top = 16.dp, bottom = 4.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        // Wraps the score below the name at large text sizes instead of squeezing either.
        FlowRow(
            Modifier.fillMaxWidth().semantics(mergeDescendants = true) {},
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalArrangement = Arrangement.spacedBy(6.dp),
            itemVerticalAlignment = Alignment.CenterVertically,
        ) {
            Column {
                Text(
                    stringResource(R.string.leaderboard_you).uppercase(),
                    fontSize = 12.sp,
                    fontWeight = FontWeight.ExtraBold,
                    letterSpacing = 0.8.sp,
                    color = palette.primary,
                )
                Text(name, fontSize = 18.sp, fontWeight = FontWeight.Bold, color = palette.textPrimary)
            }
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Icon(
                    if (isStars) Icons.Filled.Star else Icons.Filled.LocalFireDepartment,
                    contentDescription = stringResource(if (isStars) R.string.leaderboard_tab_stars else R.string.leaderboard_tab_streak),
                    tint = palette.hardAmber,
                    modifier = Modifier.size(26.dp),
                )
                Text(
                    "${snapshot.ownScore}",
                    fontSize = 34.sp,
                    fontWeight = FontWeight.ExtraBold,
                    color = palette.textPrimary,
                    maxLines = 1,
                )
            }
        }
        val dashColor = palette.surfaceBorder
        Canvas(Modifier.fillMaxWidth().height(1.dp)) {
            drawLine(
                color = dashColor,
                start = Offset(0f, size.height / 2),
                end = Offset(size.width, size.height / 2),
                strokeWidth = 1.dp.toPx(),
                pathEffect = PathEffect.dashPathEffect(floatArrayOf(5.dp.toPx(), 4.dp.toPx())),
            )
        }
        Text(status, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = palette.textPrimary)
        TextButton(onClick = onChangeName, enabled = canChangeName, contentPadding = PaddingValues(horizontal = 0.dp)) {
            Icon(Icons.Filled.Edit, contentDescription = null, tint = palette.primary, modifier = Modifier.size(16.dp))
            Spacer(Modifier.size(6.dp))
            Text(
                stringResource(R.string.leaderboard_change_name),
                fontSize = 14.sp,
                fontWeight = FontWeight.Bold,
                color = palette.primary,
            )
        }
    }
}

@Composable
private fun BoardRow(
    rank: Int,
    name: String,
    score: Int,
    board: LeaderboardBoard,
    isOwn: Boolean,
    isFirst: Boolean,
    isLast: Boolean,
) {
    val palette = LocalPalette.current
    val medal = when (rank) {
        1 -> palette.medalGold
        2 -> palette.medalSilver
        3 -> palette.medalBronze
        else -> null
    }
    val shape = RoundedCornerShape(
        topStart = if (isFirst) 16.dp else 0.dp,
        topEnd = if (isFirst) 16.dp else 0.dp,
        bottomStart = if (isLast) 16.dp else 0.dp,
        bottomEnd = if (isLast) 16.dp else 0.dp,
    )
    Column(
        Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(palette.surfacePrimary)
            .semantics(mergeDescendants = true) {},
    ) {
        Row(
            Modifier
                .fillMaxWidth()
                .background(if (isOwn) palette.primary.copy(alpha = 0.1f) else Color.Transparent)
                .padding(horizontal = 14.dp, vertical = 11.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Box(
                Modifier
                    .size(30.dp)
                    .then(if (medal != null) Modifier.background(medal, CircleShape) else Modifier),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    "$rank",
                    fontSize = 14.sp,
                    fontWeight = FontWeight.ExtraBold,
                    color = if (medal != null) palette.onMedal else palette.textSecondary,
                    maxLines = 1,
                )
            }
            Column(Modifier.weight(1f)) {
                Text(
                    name,
                    fontSize = 15.sp,
                    fontWeight = if (isOwn) FontWeight.Bold else FontWeight.Medium,
                    color = palette.textPrimary,
                )
                if (isOwn) {
                    Text(
                        stringResource(R.string.leaderboard_you),
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold,
                        color = palette.primary,
                    )
                }
            }
            BoardScore(score, board)
        }
        if (!isLast) HorizontalDivider(color = palette.surfaceBorder)
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
