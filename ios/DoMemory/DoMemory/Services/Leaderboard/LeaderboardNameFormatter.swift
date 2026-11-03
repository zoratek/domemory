//
//  LeaderboardNameFormatter.swift
//  DoMemory
//
//  Turns a player's two word numbers into a name in the reader's language.
//  localization/leaderboard-names.json is shared with Android: each language has
//  its own word order, and adjectives agree with the animal's gender where the
//  language requires it.
//

import Foundation

struct LeaderboardNameFormatter {
    struct Animal: Decodable {
        let word: String
        let gender: String
    }

    struct Language: Decodable {
        let format: String
        let adjectives: [[String]]
        let animals: [Animal]
    }

    static let current = LeaderboardNameFormatter(
        language: loadLanguages()[Bundle.main.preferredLocalizations.first ?? "en"]
    )

    private let language: Language?

    init(language: Language?) {
        self.language = language
    }

    func name(_ words: LeaderboardNameWords) -> String {
        guard let language,
              language.adjectives.indices.contains(words.adjective),
              language.animals.indices.contains(words.animal) else {
            return Self.englishName(words)
        }
        return language.format
            .replacingOccurrences(of: "{adjective}", with: adjective(words.adjective, agreeingWith: words.animal))
            .replacingOccurrences(of: "{animal}", with: language.animals[words.animal].word)
    }

    /// The adjective alone, in the form that agrees with `animal`.
    func adjective(_ index: Int, agreeingWith animal: Int) -> String {
        guard let language, language.adjectives.indices.contains(index), language.animals.indices.contains(animal) else {
            return LeaderboardNames.adjectives.indices.contains(index) ? LeaderboardNames.adjectives[index] : ""
        }
        let forms = language.adjectives[index]
        let form: Int
        switch language.animals[animal].gender {
        case "f": form = 1
        case "n": form = 2
        default: form = 0
        }
        return forms.indices.contains(form) ? forms[form] : forms.first ?? ""
    }

    func animal(_ index: Int) -> String {
        guard let language, language.animals.indices.contains(index) else {
            return LeaderboardNames.animals.indices.contains(index) ? LeaderboardNames.animals[index] : ""
        }
        return language.animals[index].word
    }

    private static func englishName(_ words: LeaderboardNameWords) -> String {
        guard LeaderboardNames.isValid(adjective: words.adjective, animal: words.animal) else { return "" }
        return "\(LeaderboardNames.adjectives[words.adjective]) \(LeaderboardNames.animals[words.animal])"
    }

    static func loadLanguages(bundle: Bundle = .main) -> [String: Language] {
        guard let url = bundle.url(forResource: "leaderboard-names", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let languages = try? JSONDecoder().decode([String: Language].self, from: data) else {
            return [:]
        }
        return languages
    }
}
