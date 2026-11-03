package com.ezequielbrrt.domemory.services.leaderboard

import com.ezequielbrrt.domemory.services.levels.Stars
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** Reads the fixture both platforms test against, so Android can't drift from iOS. */
class LeaderboardContractTest {
    private val fixture = JSONObject(File("../../firebase/fixtures/leaderboard-v1.json").readText())

    private fun JSONArray.objects(): List<JSONObject> = List(length()) { getJSONObject(it) }

    private fun JSONArray.strings(): List<String> = List(length()) { getString(it) }

    @Test fun `word lists match the fixture in order`() {
        assertEquals(fixture.getJSONArray("adjectives").strings(), LeaderboardNames.ADJECTIVES)
        assertEquals(fixture.getJSONArray("animals").strings(), LeaderboardNames.ANIMALS)
    }

    @Test fun `default names match the fixture`() {
        fixture.getJSONArray("defaultNames").objects().forEach { item ->
            val uid = item.getString("uid")
            val words = LeaderboardNames.defaultWords(uid)
            assertEquals(uid, item.getInt("a"), words.adjective)
            assertEquals(uid, item.getInt("b"), words.animal)
            assertEquals(
                uid,
                item.getString("englishName"),
                "${LeaderboardNames.ADJECTIVES[words.adjective]} ${LeaderboardNames.ANIMALS[words.animal]}",
            )
        }
    }

    @Test fun `row order matches the fixture`() {
        val ordering = fixture.getJSONObject("ordering")
        val rows = ordering.getJSONArray("rows").objects().map {
            LeaderboardRow(it.getString("uid"), it.getInt("s"), it.getLong("t"))
        }
        assertEquals(ordering.getJSONArray("expectedOrder").strings(), LeaderboardRow.ranked(rows).map { it.uid })
    }

    @Test fun `points to the top board match the fixture`() {
        fixture.getJSONArray("starsToTopBoard").objects().forEach { item ->
            assertEquals(
                item.toString(),
                item.getInt("expected"),
                LeaderboardRow.pointsToTopBoard(item.getInt("boardSize"), item.getInt("lastRowScore"), item.getInt("ownScore")),
            )
        }
    }

    @Test fun `star awards match the fixture, which records the iOS result`() {
        fixture.getJSONArray("starAwards").objects().forEach { item ->
            val total = item.getDouble("totalSeconds")
            assertEquals(
                item.toString(),
                item.getInt("stars"),
                Stars.award(total - item.getDouble("elapsedSeconds"), total, item.getInt("failedTries")),
            )
        }
    }

    @Test fun `tick drift at an exact second can't raise a rating`() {
        // 45 s remaining reached by ticking 0.1 s, with the floating-point error that leaves.
        assertEquals(3, Stars.award(45.000000000001, 90.0, 1))
        assertEquals(2, Stars.award(44.000000000001, 90.0, 1))
    }

    @Test fun `an invalid pick falls back to the default name`() {
        val fallback = LeaderboardNames.defaultWords("u")
        assertEquals(fallback, LeaderboardNames.words(32, 0, "u"))
        assertEquals(fallback, LeaderboardNames.words(1, null, "u"))
        assertEquals(LeaderboardNameWords(1, 2), LeaderboardNames.words(1, 2, "u"))
    }

    @Test fun `malformed rows are dropped`() {
        val rows = LeaderboardRow.ranked(
            mapOf(
                "good" to mapOf("s" to 5L, "t" to 1L),
                "text" to mapOf("s" to "5", "t" to 1L),
                "noTime" to mapOf("s" to 5L),
                "negative" to mapOf("s" to -1L, "t" to 1L),
                "fraction" to mapOf("s" to 1.5, "t" to 1L),
                "notARow" to "x",
            ),
        )
        assertEquals(listOf("good"), rows.map { it.uid })
    }

    @Test fun `config fails closed`() {
        val on = mapOf("android" to mapOf("enabled" to true, "minVersion" to "1.3.0"))
        assertTrue(LeaderboardConfig.from(on).allows("1.3.0"))
        assertTrue(LeaderboardConfig.from(on).allows("1.10.0"))
        assertFalse(LeaderboardConfig.from(on).allows("1.2.0"))
        assertFalse(LeaderboardConfig.from(on).allows("unknown"))
        assertFalse(LeaderboardConfig.from(null).allows("9.9.9"))
        assertFalse(LeaderboardConfig.from("on").allows("9.9.9"))
        assertFalse(LeaderboardConfig.from(mapOf("ios" to mapOf("enabled" to true, "minVersion" to "1.0.0"))).allows("9.9.9"))
        assertFalse(LeaderboardConfig.from(mapOf("android" to mapOf("enabled" to true, "minVersion" to ""))).allows("9.9.9"))
        assertFalse(LeaderboardConfig.from(mapOf("android" to mapOf("enabled" to false, "minVersion" to "1.0.0"))).allows("9.9.9"))
    }

    // -- Shared names file -------------------------------------------------------------

    private val languages = LeaderboardNameFormatter.parse(File("../../localization/leaderboard-names.json").readText())

    @Test fun `every locale has every word`() {
        listOf("en", "es-419", "de", "fr", "hi", "it", "ja", "ko", "pt-BR", "zh-Hans").forEach { code ->
            val language = languages[code]
            assertNotNull(code, language)
            assertEquals(code, 32, language!!.adjectives.size)
            assertEquals(code, 32, language.animals.size)
            assertTrue(code, "{adjective}" in language.format && "{animal}" in language.format)
            assertTrue(code, language.adjectives.all { forms -> forms.isNotEmpty() && forms.all { it.isNotEmpty() } })
            assertTrue(code, language.animals.all { it.word.isNotEmpty() && it.gender in setOf("m", "f", "n") })
        }
    }

    @Test fun `english words match the frozen lists`() {
        val english = languages.getValue("en")
        assertEquals(LeaderboardNames.ADJECTIVES, english.adjectives.map { it.first() })
        assertEquals(LeaderboardNames.ANIMALS, english.animals.map { it.word })
    }

    @Test fun `adjectives agree with the animal`() {
        val spanish = LeaderboardNameFormatter(languages["es-419"])
        assertEquals("Nutria Tranquila", spanish.name(LeaderboardNameWords(1, 0)))
        assertEquals("Panda Tranquilo", spanish.name(LeaderboardNameWords(1, 1)))

        val german = LeaderboardNameFormatter(languages["de"])
        assertEquals("Mutiger Otter", german.name(LeaderboardNameWords(2, 0)))
        assertEquals("Mutige Eule", german.name(LeaderboardNameWords(2, 4)))
        assertEquals("Mutiges Känguru", german.name(LeaderboardNameWords(2, 18)))
        assertEquals("Heiterer Löwe", german.name(LeaderboardNameWords(10, 20)))
    }

    @Test fun `a missing language falls back to english`() {
        assertEquals("Swift Otter", LeaderboardNameFormatter(null).name(LeaderboardNameWords(0, 0)))
    }

    @Test fun `device languages map to the shipped tables`() {
        mapOf(
            "en-US" to "en", "es-MX" to "es-419", "es" to "es-419", "pt-PT" to "pt-BR", "de-DE" to "de",
            "fr-CA" to "fr", "hi-IN" to "hi", "it" to "it", "ja-JP" to "ja", "ko-KR" to "ko",
            "zh-CN" to "zh-Hans", "zh-Hans-CN" to "zh-Hans", "zh-TW" to "en", "zh-Hant-HK" to "en", "ru-RU" to "en",
        ).forEach { (tag, key) -> assertEquals(tag, key, LeaderboardNameFormatter.languageKey(tag)) }
    }
}
