package com.ezequielbrrt.domemory.services.leaderboard

import org.json.JSONObject

/**
 * Turns a player's two word numbers into a name in the reader's language.
 * `localization/leaderboard-names.json` is shared with iOS: each language has its own word
 * order, and adjectives agree with the animal's gender where the language requires it.
 */
class LeaderboardNameFormatter(private val language: Language?) {

    data class Animal(val word: String, val gender: String)

    data class Language(val format: String, val adjectives: List<List<String>>, val animals: List<Animal>)

    fun name(words: LeaderboardNameWords): String {
        val language = language
        if (language == null ||
            words.adjective !in language.adjectives.indices ||
            words.animal !in language.animals.indices
        ) {
            return englishName(words)
        }
        return language.format
            .replace("{adjective}", adjective(words.adjective, agreeingWith = words.animal))
            .replace("{animal}", language.animals[words.animal].word)
    }

    /** The adjective alone, in the form that agrees with [agreeingWith]. */
    fun adjective(index: Int, agreeingWith: Int): String {
        val language = language
        if (language == null ||
            index !in language.adjectives.indices ||
            agreeingWith !in language.animals.indices
        ) {
            return LeaderboardNames.ADJECTIVES.getOrElse(index) { "" }
        }
        val forms = language.adjectives[index]
        val form = when (language.animals[agreeingWith].gender) {
            "f" -> 1
            "n" -> 2
            else -> 0
        }
        return forms.getOrNull(form) ?: forms.firstOrNull().orEmpty()
    }

    fun animal(index: Int): String =
        language?.animals?.getOrNull(index)?.word ?: LeaderboardNames.ANIMALS.getOrElse(index) { "" }

    private fun englishName(words: LeaderboardNameWords): String =
        if (LeaderboardNames.isValid(words.adjective, words.animal)) {
            "${LeaderboardNames.ADJECTIVES[words.adjective]} ${LeaderboardNames.ANIMALS[words.animal]}"
        } else {
            ""
        }

    companion object {
        fun parse(json: String): Map<String, Language> = runCatching {
            val root = JSONObject(json)
            root.keys().asSequence().associateWith { code ->
                val language = root.getJSONObject(code)
                val adjectives = language.getJSONArray("adjectives")
                val animals = language.getJSONArray("animals")
                Language(
                    format = language.getString("format"),
                    adjectives = List(adjectives.length()) { index ->
                        val forms = adjectives.getJSONArray(index)
                        List(forms.length()) { forms.getString(it) }
                    },
                    animals = List(animals.length()) { index ->
                        val animal = animals.getJSONObject(index)
                        Animal(animal.getString("word"), animal.getString("gender"))
                    },
                )
            }
        }.getOrDefault(emptyMap())

        /**
         * The names-file key for a BCP 47 tag, matching the languages the app's string tables
         * resolve to. Traditional Chinese has no string table, so it stays in English like the
         * rest of the app does.
         */
        fun languageKey(languageTag: String): String {
            val parts = languageTag.replace('_', '-').split("-")
            return when (val language = parts.first().lowercase()) {
                "es" -> "es-419"
                "pt" -> "pt-BR"
                "zh" -> if (parts.any { it.equals("Hant", ignoreCase = true) || it.uppercase() in setOf("TW", "HK", "MO") }) "en" else "zh-Hans"
                "de", "fr", "hi", "it", "ja", "ko" -> language
                else -> "en"
            }
        }
    }
}
