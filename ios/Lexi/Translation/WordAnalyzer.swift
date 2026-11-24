import Foundation
import NaturalLanguage

/// Lemma and part of speech on device with NaturalLanguage
/// (`.lexicalClass`, `.lemma` and `.nameType` tag schemes).
enum WordAnalyzer {
    struct Analysis: Equatable {
        var lemma: String
        var partOfSpeech: String
    }

    static func analyze(sentence: String, word: String, offset: Int) -> Analysis {
        let fallback = Analysis(lemma: word.lowercased(), partOfSpeech: "")
        let ns = sentence as NSString
        let len = (word as NSString).length
        var r = NSRange(location: offset, length: len)
        if offset < 0 || r.upperBound > ns.length || ns.substring(with: r) != word { r = ns.range(of: word) }
        guard r.location != NSNotFound, let range = Range(r, in: sentence) else { return fallback }

        let tagger = NLTagger(tagSchemes: [.lexicalClass, .lemma, .nameType])
        tagger.string = sentence
        tagger.setLanguage(.english, range: sentence.startIndex..<sentence.endIndex)
        let at = range.lowerBound
        let cls = tagger.tag(at: at, unit: .word, scheme: .lexicalClass).0
        let lemmaTag = tagger.tag(at: at, unit: .word, scheme: .lemma).0
        let name = tagger.tag(at: at, unit: .word, scheme: .nameType).0

        // Hyphenated words and contractions are split by the tagger; keep the whole word then.
        let single = !word.contains("-") && !word.contains("’") && !word.contains("'")
        var lemma = single ? (lemmaTag?.rawValue.lowercased() ?? word.lowercased()) : word.lowercased()
        if lemma.isEmpty { lemma = word.lowercased() }

        var pos: String
        switch cls {
        case .noun?:
            if name == .personalName || name == .placeName || name == .organizationName { pos = "proper noun" }
            else { pos = lemma != word.lowercased() ? "noun, plural" : "noun" }
        case .verb?: pos = "verb"
        case .adjective?: pos = "adjective"
        case .adverb?: pos = "adverb"
        case .pronoun?: pos = "pronoun"
        case .determiner?: pos = "determiner"
        case .preposition?: pos = "preposition"
        case .conjunction?: pos = "conjunction"
        case .particle?: pos = "particle"
        case .number?: pos = "number"
        case .interjection?: pos = "interjection"
        case .idiom?: pos = "idiom"
        default: pos = ""
        }
        return Analysis(lemma: lemma, partOfSpeech: pos)
    }
}
