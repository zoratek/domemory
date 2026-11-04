package com.ezequielbrrt.domemory.feature.whatsnew

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.Shuffle
import androidx.compose.material.icons.filled.Star
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.res.stringResource
import com.ezequielbrrt.domemory.BuildConfig
import com.ezequielbrrt.domemory.R
import com.ezequielbrrt.domemory.ui.theme.DoMemoryType
import com.ezequielbrrt.domemory.ui.theme.LocalPalette
import com.ezequielbrrt.domemory.ui.theme.Palette
import com.ezequielbrrt.whatsnewkit.WhatsNewScreen
import com.ezequielbrrt.whatsnewkit.model.WhatsNew
import com.ezequielbrrt.whatsnewkit.model.WhatsNewItem
import com.ezequielbrrt.whatsnewkit.theme.WhatsNewTheme

/**
 * The What's New screen for the running app version, presented by WhatsNewKit-Android
 * (the `:whatsnewkit` module vendored under `android/WhatsNewKit-Android`).
 *
 * Content and theme are the Android counterparts of iOS's `WhatsNewContent.swift`:
 * `WhatsNew.current` and `WhatsNewTheme.doMemory`. Like iOS, the app keeps its own version
 * gate (`services/whatsnew/WhatsNewManager`, spec 15.1's `whatsNewLastSeenVersion`) rather
 * than the library's `WhatsNewVersionTracker`; the library only draws the screen.
 *
 * Intentionally reused for the automatic post-upgrade presentation and the Settings
 * "What's New" row — the caller decides whether dismissal marks the version as seen.
 */
@Composable
fun DoMemoryWhatsNewScreen(onDismiss: () -> Unit) {
    val palette = LocalPalette.current
    val whatsNew = rememberCurrentWhatsNew()
    val theme = remember(palette) { palette.whatsNewTheme() }
    WhatsNewScreen(whatsNew = whatsNew, onDismiss = onDismiss, theme = theme)
}

/**
 * Release notes for the running version. Icons stand in for the SF Symbols the iOS items
 * carry; strings are the same `whats_new_*` resources the previous dialog showed.
 *
 * Remembered because [WhatsNewItem] mints a random `id` per instance, and rebuilding the
 * list on every recomposition would hand the card new item identities each frame.
 */
@Composable
private fun rememberCurrentWhatsNew(): WhatsNew {
    val title = stringResource(R.string.whats_new_title)
    val button = stringResource(R.string.whats_new_button)
    val items = listOf(
        Triple(stringResource(R.string.whats_new_leaderboard_title), stringResource(R.string.whats_new_leaderboard_description), Icons.Filled.EmojiEvents),
        Triple(stringResource(R.string.whats_new_your_score_title), stringResource(R.string.whats_new_your_score_description), Icons.Filled.Star),
        Triple(stringResource(R.string.whats_new_pick_name_title), stringResource(R.string.whats_new_pick_name_description), Icons.Filled.Edit),
        Triple(stringResource(R.string.whats_new_multiplayer_shuffle_title), stringResource(R.string.whats_new_multiplayer_shuffle_description), Icons.Filled.Shuffle),
    )
    return remember(title, button, items) {
        WhatsNew(
            title = title,
            version = BuildConfig.VERSION_NAME,
            items = items.map { (itemTitle, description, icon) ->
                WhatsNewItem(title = itemTitle, description = description, icon = icon)
            },
            primaryButtonTitle = button,
        )
    }
}

/**
 * Port of iOS's `WhatsNewTheme.doMemory`: built from the app palette rather than the
 * Material scheme, with the card reusing the Settings row surface tokens so the screen reads
 * as part of DoMemory in both appearances. `cardBackgroundColor` is an opaque tint over the
 * library's translucent material layer, which is the closest Android gets to iOS's
 * `surfacePrimary` card over a thin material. Text styles follow spec 14.2: the display face
 * for the headline, Material defaults for everything else, as on iOS.
 */
internal fun Palette.whatsNewTheme(): WhatsNewTheme = WhatsNewTheme(
    accentColor = primary,
    backgroundColor = appBackground,
    titleColor = textPrimary,
    versionColor = primary,
    versionBackgroundColor = primary.copy(alpha = 0.14f),
    itemTitleColor = textPrimary,
    itemDescriptionColor = textSecondary,
    symbolColor = primary,
    symbolBackgroundColor = primary.copy(alpha = 0.14f),
    cardBackgroundColor = surfacePrimary,
    cardBorderColor = surfaceBorder,
    cardShadowColor = shadow,
    separatorColor = surfaceBorder,
    titleTextStyle = DoMemoryType.display(30),
)
