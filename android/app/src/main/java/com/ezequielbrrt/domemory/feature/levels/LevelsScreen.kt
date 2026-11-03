package com.ezequielbrrt.domemory.feature.levels

import androidx.compose.animation.core.EaseInOut
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.automirrored.outlined.HelpOutline
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.platform.LocalContext
import com.ezequielbrrt.domemory.R
import com.ezequielbrrt.domemory.feature.leaderboard.LeaderboardNoticeCard
import com.ezequielbrrt.domemory.services.ads.AdPlacement
import com.ezequielbrrt.domemory.services.ads.AdsService
import com.ezequielbrrt.domemory.services.ads.findActivity
import com.ezequielbrrt.domemory.services.analytics.AnalyticsEvent
import com.ezequielbrrt.domemory.services.analytics.AnalyticsService
import com.ezequielbrrt.domemory.services.haptics.HapticIntent
import com.ezequielbrrt.domemory.services.haptics.HapticsService
import com.ezequielbrrt.domemory.services.levels.LevelLivesService
import com.ezequielbrrt.domemory.services.levels.LevelPowerUp
import com.ezequielbrrt.domemory.ui.anim.pressScaleClickable
import com.ezequielbrrt.domemory.ui.anim.rememberReduceMotion
import com.ezequielbrrt.domemory.ui.components.IntroCarousel
import com.ezequielbrrt.domemory.ui.components.IntroSlide
import com.ezequielbrrt.domemory.ui.components.LivesRow
import com.ezequielbrrt.domemory.ui.lottie.BundledLottie
import com.ezequielbrrt.domemory.ui.theme.DoMemoryType
import com.ezequielbrrt.domemory.ui.theme.LocalPalette
import com.ezequielbrrt.domemory.ui.theme.Palette
import kotlinx.coroutines.launch

/**
 * Endless procedural level map (spec 7.8-7.9). Tiles come straight from
 * [LevelsViewModel]'s underlying [com.ezequielbrrt.domemory.services.levels.LevelProgressService];
 * lives/star display and the out-of-lives gate come from the view model's [LevelsViewModel.UiState].
 */
@Composable
fun LevelsScreen(viewModel: LevelsViewModel, onLevelSelected: (Int) -> Unit) {
    LaunchedEffect(Unit) {
        // The notice may have been answered on the leaderboard tab.
        viewModel.refreshLeaderboard()
        AnalyticsService.log(AnalyticsEvent.ScreenView(screenName = "levels", screenClass = "LevelsScreen"))
    }
    // Recomposes the tile grid whenever cached progress changes (spec 2's fix: stars
    // and unlocks now arrive as a StateFlow, not a manually-invalidated cache).
    viewModel.progressRevision.collectAsState().value
    val uiState by viewModel.uiState.collectAsState()
    val palette = LocalPalette.current
    val coroutineScope = rememberCoroutineScope()
    val context = LocalContext.current
    val activity = remember(context) { context.findActivity() }

    val highest = viewModel.highestUnlockedLevel
    val levels = (1..(highest + 20)).toList()

    Box(Modifier.fillMaxSize().background(palette.appBackground)) {
        Column(Modifier.fillMaxSize()) {
            LevelsHeader(
                currentLevel = highest,
                livesRemaining = uiState.livesRemaining,
                livesEffect = uiState.livesEffect,
                onLivesEffectFinished = viewModel::consumeLivesEffect,
                starBalance = uiState.starBalance,
                starsCredited = uiState.starsCredited,
                onStarsCreditedFinished = viewModel::consumeStarsCredited,
                onInfoClick = { HapticsService.fire(HapticIntent.TAP); viewModel.presentIntro() },
            )
            uiState.leaderboardNoticeName?.let { name ->
                LeaderboardNoticeCard(
                    name = name,
                    onAccept = viewModel::acceptLeaderboardNotice,
                    onDecline = viewModel::declineLeaderboardNotice,
                    modifier = Modifier.padding(horizontal = 20.dp),
                )
            }
            LazyVerticalGrid(
                columns = GridCells.Fixed(4),
                contentPadding = PaddingValues(20.dp),
                horizontalArrangement = Arrangement.spacedBy(18.dp),
                verticalArrangement = Arrangement.spacedBy(22.dp),
            ) {
                items(levels) { level ->
                    val unlocked = viewModel.isUnlocked(level)
                    val stars = viewModel.stars(level)
                    val isCurrent = level == highest
                    LevelTile(
                        level = level,
                        unlocked = unlocked,
                        isCurrent = isCurrent,
                        stars = stars,
                        onClick = {
                            coroutineScope.launch {
                                if (viewModel.attemptStart(level)) onLevelSelected(level)
                            }
                        },
                    )
                }
            }
        }

        if (uiState.showOutOfLivesPrompt) {
            LaunchedEffect(Unit) {
                if (AdsService.isRewardedConfigured(AdPlacement.LEVELS_REWARDED_LIFE)) {
                    context.applicationContext.let { AdsService.loadRewarded(it, AdPlacement.LEVELS_REWARDED_LIFE) }
                }
            }
            OutOfLivesModal(
                starBalance = uiState.starBalance,
                canWatchAd = AdsService.isRewardedConfigured(AdPlacement.LEVELS_REWARDED_LIFE),
                onWatchAd = {
                    // Matches iOS's OutOfLivesModal: TAP on the button itself; the eventual
                    // .reward fires separately from applyLifeRewardFromAd() once the ad
                    // actually pays out.
                    HapticsService.fire(HapticIntent.TAP)
                    AdsService.showRewarded(
                        activity = activity,
                        placement = AdPlacement.LEVELS_REWARDED_LIFE,
                        onReward = { viewModel.applyLifeRewardFromAd() },
                    )
                },
                // No TAP here — buyLifeWithStars() fires its own .reward on a successful
                // spend, and iOS's own comment on this exact button says a .tap here would
                // double-buzz.
                onBuyWithStars = viewModel::buyLifeWithStars,
                onDismiss = { HapticsService.fire(HapticIntent.TAP); viewModel.dismissOutOfLivesPrompt() },
            )
        }

        // uiState.showIntro itself is read one level up, in NavGraph.kt's Menu composable —
        // not here. LevelsScreen is only ever composed as the Levels tab's *content*, below
        // the Menu header, cards and tab row; iOS's own `.fullScreenCover(isPresented:
        // $showIntro)` (LevelsView.swift) covers the *entire* screen, that chrome included,
        // so LevelsIntroOverlay has to be a sibling of MenuScreen, not a child of this
        // composable, or it would only ever cover the tab body underneath that chrome.
    }
}

@Composable
private fun LevelsHeader(
    currentLevel: Int,
    livesRemaining: Int,
    livesEffect: LivesEffect?,
    onLivesEffectFinished: () -> Unit,
    starBalance: Int,
    starsCredited: Boolean,
    onStarsCreditedFinished: () -> Unit,
    onInfoClick: () -> Unit,
) {
    val palette = LocalPalette.current
    val infoAccessibilityLabel = stringResource(R.string.levels_intro_info_accessibility)
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 16.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    stringResource(R.string.levels_screen_title),
                    style = DoMemoryType.display(20),
                    color = palette.textPrimary,
                )
                // SF Symbol `questionmark.circle` (LevelsView.swift) — a real vector icon
                // rather than the bare "?" glyph this used before material-icons-extended
                // was added (spec 14.3's "map each SF Symbol to a Material Symbol").
                IconButton(
                    onClick = onInfoClick,
                    modifier = Modifier.semantics { contentDescription = infoAccessibilityLabel },
                ) {
                    Icon(Icons.AutoMirrored.Outlined.HelpOutline, contentDescription = null, tint = palette.textSecondary)
                }
            }
            Text(
                stringResource(R.string.levels_current_level_format, currentLevel),
                fontSize = 13.sp,
                color = palette.textSecondary,
            )
        }
        Column(horizontalAlignment = Alignment.End) {
            // Matches iOS's LevelsView.swift header: the lives row gets the same pill
            // treatment as the star counter beside it, not a bare row of glyphs. Carries
            // the heart-break/refill Lottie effect (spec 14.4 polish, `1dc9282`'s
            // "LivesRow effects on both platforms").
            LivesPill(livesRemaining, effect = livesEffect, onEffectFinished = onLivesEffectFinished)
            Spacer(Modifier.size(6.dp))
            StarBalancePill(starBalance, credited = starsCredited, onCreditedFinished = onStarsCreditedFinished)
        }
    }
}

/**
 * [com.ezequielbrrt.domemory.ui.components.LivesRow] wrapped in the same capsule pill as
 * the star counter (`LevelsView.swift:130-137`: `LivesRow` inside a `Capsule` filled
 * `surfacePrimary`, stroked `surfaceBorder`). Shared by the endless map and the season map.
 */
@Composable
fun LivesPill(
    remaining: Int,
    total: Int = LevelLivesService.MAX_LIVES,
    effect: LivesEffect? = null,
    onEffectFinished: (() -> Unit)? = null,
) {
    val palette = LocalPalette.current
    Surface(
        shape = RoundedCornerShape(50),
        color = palette.surfacePrimary,
        border = BorderStroke(1.dp, palette.surfaceBorder),
    ) {
        Box(Modifier.padding(horizontal = 10.dp, vertical = 6.dp)) {
            LivesRow(remaining = remaining, total = total, effect = effect, onEffectFinished = onEffectFinished)
        }
    }
}

/** A capsule pill of plain text, e.g. a season's `cleared / total` progress. Public so the
 * season map can reuse the exact same treatment as the endless map. */
@Composable
fun Pill(text: String, accessibilityLabel: String? = null) {
    val palette = LocalPalette.current
    Surface(
        shape = RoundedCornerShape(50),
        color = palette.surfacePrimary,
        border = BorderStroke(1.dp, palette.surfaceBorder),
        modifier = if (accessibilityLabel != null) {
            Modifier.semantics { contentDescription = accessibilityLabel }
        } else {
            Modifier
        },
    ) {
        Text(
            text,
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
            fontSize = 12.sp,
            fontWeight = FontWeight.Bold,
            color = palette.textPrimary,
        )
    }
}

/**
 * The star-balance pill (`LevelsView.swift`'s trailing "★ N" capsule): a star glyph, a
 * sparkle Lottie clip that plays over it on a credit (never a spend — `1dc9282`'s
 * "star-sparkle over the header star chip on a credit"), and the count. Public so the
 * season map's identical wallet-balance pill can reuse it.
 */
@Composable
fun StarBalancePill(balance: Int, credited: Boolean = false, onCreditedFinished: (() -> Unit)? = null) {
    val palette = LocalPalette.current
    val reduceMotion = rememberReduceMotion()
    val accessibilityLabel = stringResource(R.string.levels_star_balance_format, balance)
    Surface(
        shape = RoundedCornerShape(50),
        color = palette.surfacePrimary,
        border = BorderStroke(1.dp, palette.surfaceBorder),
        // Spec 14.5: "the star balance announces 'N stars available'" — the visible glyph
        // ("★ 12") stays compact, but a screen reader gets the full sentence instead.
        modifier = Modifier.semantics { contentDescription = accessibilityLabel },
    ) {
        Row(
            Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Box(contentAlignment = Alignment.Center) {
                Icon(Icons.Filled.Star, contentDescription = null, tint = palette.hardAmber, modifier = Modifier.size(14.dp))
                if (credited && !reduceMotion) {
                    BundledLottie(
                        name = "star-sparkle",
                        tint = palette.hardAmber,
                        modifier = Modifier.size(40.dp),
                        onFinished = onCreditedFinished,
                    )
                }
            }
            Text(
                balance.toString(),
                fontSize = 12.sp,
                fontWeight = FontWeight.Bold,
                color = palette.textPrimary,
            )
        }
    }
}

@Composable
/** Shared circular node used by both the endless and finite season level maps. */
fun LevelTile(
    level: Int,
    unlocked: Boolean,
    isCurrent: Boolean,
    stars: Int,
    onClick: () -> Unit,
) {
    val palette = LocalPalette.current
    val background = when {
        isCurrent -> palette.primary
        unlocked -> palette.surfacePrimary
        else -> palette.surfaceSecondary
    }
    val foreground = when {
        isCurrent -> palette.surfacePrimary
        unlocked -> palette.primary
        else -> palette.textSecondary
    }

    // Ported from iOS's `LevelTileView` (`LevelMapView.swift`): only the `.current` tile
    // pulses — a ring that grows/fades outward plus a subtle scale on the tile itself, looped
    // forever. Calling `rememberInfiniteTransition`/`animateFloat` inside this `if` branch
    // (rather than unconditionally and hiding the result) is what gives the Compose analog of
    // iOS's `onAppear` + `onChange(of: tile.isCurrent)` re-trigger for free: whenever a tile
    // transitions into `.current` — which iOS's own comment notes is usually a tile that was
    // already on screen as `.locked`, not a freshly appearing one — this branch re-enters
    // composition and the animation starts from zero again. Every other tile pays nothing.
    val pulseProgress: Float? = if (isCurrent) {
        val infiniteTransition = rememberInfiniteTransition(label = "levelTilePulse")
        val progress by infiniteTransition.animateFloat(
            initialValue = 0f,
            targetValue = 1f,
            animationSpec = infiniteRepeatable(
                animation = tween(durationMillis = 1100, easing = EaseInOut),
                repeatMode = RepeatMode.Reverse,
            ),
            label = "levelTilePulseProgress",
        )
        progress
    } else {
        null
    }

    Column(
        modifier = Modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            modifier = Modifier.size(64.dp),
            contentAlignment = Alignment.Center,
        ) {
            if (pulseProgress != null) {
                Box(
                    Modifier
                        .matchParentSize()
                        .graphicsLayer {
                            val ringScale = 1f + pulseProgress * 0.45f
                            scaleX = ringScale
                            scaleY = ringScale
                            alpha = 0.7f * (1f - pulseProgress)
                        }
                        .border(3.dp, palette.primary, CircleShape),
                )
            }

            Box(
                modifier = Modifier
                    .matchParentSize()
                    .graphicsLayer {
                        val tileScale = 1f + (pulseProgress ?: 0f) * 0.06f
                        scaleX = tileScale
                        scaleY = tileScale
                    }
                    .background(background, CircleShape)
                    .border(if (isCurrent) 3.dp else 1.5.dp, if (isCurrent) palette.primary else palette.surfaceBorder, CircleShape)
                    .pressScaleClickable(enabled = unlocked, onClick = onClick),
                contentAlignment = Alignment.Center,
            ) {
                if (unlocked) {
                    Text(
                        text = level.toString(),
                        fontSize = if (isCurrent) 26.sp else 24.sp,
                        fontWeight = if (isCurrent) FontWeight.Black else FontWeight.Bold,
                        color = foreground,
                    )
                } else {
                    // SF Symbol `lock.fill` (LevelMapView.swift:189-192) — a real vector icon
                    // rather than the "🔒" emoji glyph this used before material-icons-extended
                    // was added.
                    Icon(
                        Icons.Filled.Lock,
                        contentDescription = null,
                        tint = foreground,
                        modifier = Modifier.size(20.dp),
                    )
                }
            }
        }
        // Matches iOS's `starsRow` (LevelMapView.swift:213-226): always 3 slots, filled
        // (hardAmber) vs. muted-outline, so a 1-star clear still reads as "out of 3"
        // instead of a single lonely star.
        Row(
            modifier = Modifier.height(14.dp),
            horizontalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            if (stars > 0) {
                repeat(3) { index ->
                    Icon(
                        Icons.Filled.Star,
                        contentDescription = null,
                        tint = if (index < stars) palette.hardAmber else palette.textSecondary.copy(alpha = 0.3f),
                        modifier = Modifier.size(11.dp),
                    )
                }
            }
        }
    }
}

/** Shown from the level map when tapping a tile with no lives left today (spec 7.4).
 * Public so the season map (Phase 3) can reuse it verbatim. */
@Composable
fun OutOfLivesModal(
    starBalance: Int,
    canWatchAd: Boolean,
    onWatchAd: () -> Unit,
    onBuyWithStars: () -> Unit,
    onDismiss: () -> Unit,
) {
    val palette = LocalPalette.current
    val canBuyWithStars = starBalance >= LevelPowerUp.LIFE_COST
    Box(Modifier.fillMaxSize().background(palette.overlayBackdrop), contentAlignment = Alignment.Center) {
        Surface(
            shape = RoundedCornerShape(28.dp),
            color = palette.surfacePrimary,
            border = BorderStroke(1.dp, palette.surfaceBorder),
        ) {
            Column(
                Modifier.padding(28.dp).fillMaxWidth(),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text("💔", fontSize = 56.sp)
                Spacer(Modifier.height(12.dp))
                Text(
                    stringResource(R.string.levels_out_of_lives_title),
                    style = DoMemoryType.display(22),
                    color = palette.textPrimary,
                    textAlign = TextAlign.Center,
                )
                Spacer(Modifier.height(12.dp))
                LivesRow(remaining = 0)
                Spacer(Modifier.height(12.dp))
                Text(
                    // Message text mirrors whether a rewarded-ad refill is actually on offer
                    // (spec 7.4) rather than always assuming the star-only wording.
                    stringResource(
                        if (canWatchAd) R.string.levels_out_of_lives_message
                        else R.string.levels_out_of_lives_message_no_ad,
                    ),
                    color = palette.textSecondary,
                    fontSize = 14.sp,
                    textAlign = TextAlign.Center,
                )
                Spacer(Modifier.height(28.dp))
                Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    if (canWatchAd) {
                        Button(
                            onClick = onWatchAd,
                            modifier = Modifier.fillMaxWidth(),
                            shape = RoundedCornerShape(50),
                            contentPadding = PaddingValues(vertical = 16.dp),
                            colors = ButtonDefaults.buttonColors(containerColor = palette.hardAmber),
                        ) {
                            Text(
                                stringResource(R.string.levels_watch_ad_for_life),
                                fontWeight = FontWeight.Bold,
                                color = Color.White,
                            )
                        }
                    }
                    if (canBuyWithStars) {
                        OutlinedButton(
                            onClick = onBuyWithStars,
                            modifier = Modifier.fillMaxWidth(),
                            shape = RoundedCornerShape(50),
                            contentPadding = PaddingValues(vertical = 16.dp),
                            border = BorderStroke(1.5.dp, palette.hardAmber.copy(alpha = 0.5f)),
                        ) {
                            Text(
                                stringResource(R.string.levels_buy_life_format, LevelPowerUp.LIFE_COST),
                                fontWeight = FontWeight.Bold,
                                color = palette.hardAmber,
                            )
                        }
                    }
                    OutlinedButton(
                        onClick = onDismiss,
                        modifier = Modifier.fillMaxWidth(),
                        shape = RoundedCornerShape(50),
                        contentPadding = PaddingValues(vertical = 16.dp),
                        border = BorderStroke(1.5.dp, palette.primary.copy(alpha = 0.4f)),
                    ) {
                        Text(
                            stringResource(R.string.common_cancel),
                            fontWeight = FontWeight.SemiBold,
                            color = palette.primary,
                        )
                    }
                }
            }
        }
    }
}

/**
 * A full-screen, swipeable 4-slide carousel (spec 7.9), reachable from the map's info
 * button. The chrome — pager, dots, Skip, capsule Next/Done button — lives in the shared
 * [IntroCarousel], the same way iOS's `LevelsIntroView` and `FeatureIntroView` share
 * `IntroCarouselView`, so the two intros cannot drift apart.
 *
 * Public, and deliberately **not** called from [LevelsScreen] itself: iOS presents this
 * with `.fullScreenCover`, which covers the whole screen — Menu's header, cards and tab
 * row included — not just the Levels tab's own content area. `NavGraph.kt`'s Menu
 * composable renders this as a sibling of `MenuScreen`, the same way it layers
 * `NotificationPrimerHost`, to get that same true full-screen coverage.
 */
@Composable
fun LevelsIntroOverlay(onDismiss: () -> Unit, source: String = "info_button") {
    LaunchedEffect(Unit) {
        AnalyticsService.log(AnalyticsEvent.ScreenView(screenName = "levels_intro", screenClass = "LevelsIntroOverlay"))
        AnalyticsService.log(AnalyticsEvent.LevelsIntroShown(source = source))
    }

    val slides = listOf(
        IntroSlide(
            icon = Icons.Filled.EmojiEvents,
            color = { it.easyGreen },
            title = stringResource(R.string.levels_intro_progress_title),
            subtitle = stringResource(R.string.levels_intro_progress_subtitle),
        ),
        IntroSlide(
            icon = Icons.Filled.Star,
            color = { it.hardAmber },
            title = stringResource(R.string.levels_intro_stars_title),
            subtitle = stringResource(R.string.levels_intro_stars_subtitle),
        ),
        IntroSlide(
            icon = Icons.Filled.Favorite,
            color = { it.secondary },
            title = stringResource(R.string.levels_intro_lives_title),
            subtitle = stringResource(R.string.levels_intro_lives_subtitle, LevelLivesService.MAX_LIVES),
        ),
        // Neutral primary rather than the success green — a green X reads as "you passed",
        // the opposite of what this slide teaches (mirrors IntroCarouselView.swift's own comment).
        IntroSlide(
            icon = Icons.Filled.Cancel,
            color = { it.primary },
            title = stringResource(R.string.levels_intro_mistakes_title),
            subtitle = stringResource(R.string.levels_intro_mistakes_subtitle),
        ),
    )

    IntroCarousel(
        slides = slides,
        finishTitle = stringResource(R.string.levels_intro_done),
        onSkip = { slidesSeen ->
            AnalyticsService.log(AnalyticsEvent.LevelsIntroSkipped(slidesSeen = slidesSeen))
            onDismiss()
        },
        onFinish = {
            AnalyticsService.log(AnalyticsEvent.LevelsIntroCompleted)
            onDismiss()
        },
    )
}
