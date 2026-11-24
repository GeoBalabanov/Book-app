import Foundation
import SwiftData

/// A word saved from the reader. Also a flashcard: the review fields hold its
/// SM-2 scheduling state (see web/js/srs/sm2.js).
@Model
final class SavedWord {
    @Attribute(.unique) var id: String
    var word: String                  // as it appeared ("ran")
    var lemma: String                 // base form ("run")
    var partOfSpeech: String
    var translation: String           // Bulgarian, as used in the sentence
    var dictionaryTranslation: String // Bulgarian for the lemma
    var sentence: String
    var offset: Int                   // UTF-16 index of `word` in `sentence`
    var sentenceTranslation: String
    var bookID: String
    var bookTitle: String
    var addedAt: Date

    // Review data (SM-2). A new card is due immediately.
    var ease: Double
    var interval: Double              // days
    var repetitions: Int
    var lapses: Int
    var due: Date
    var lastReviewed: Date?

    init(request: LookupRequest, result: LookupResult, now: Date = .now) {
        id = UUID().uuidString
        word = request.word
        lemma = result.lemma
        partOfSpeech = result.partOfSpeech
        translation = result.translation
        dictionaryTranslation = result.dictionaryTranslation
        sentence = request.sentence
        offset = request.offset
        sentenceTranslation = result.sentenceTranslation
        bookID = request.bookID
        bookTitle = request.bookTitle
        addedAt = now
        ease = 2.5
        interval = 0
        repetitions = 0
        lapses = 0
        due = now
        lastReviewed = nil
    }

    var asRequest: LookupRequest {
        LookupRequest(word: word, sentence: sentence, offset: offset, bookTitle: bookTitle, bookID: bookID)
    }

    var asResult: LookupResult {
        LookupResult(word: word, lemma: lemma, partOfSpeech: partOfSpeech, translation: translation,
                     dictionaryTranslation: dictionaryTranslation, sentenceTranslation: sentenceTranslation, provider: "")
    }
}

extension Collection where Element == SavedWord {
    /// Lowercased forms to underline in the reader: surface words and single-word lemmas.
    var underlineForms: Set<String> {
        var set = Set<String>()
        for w in self {
            if !w.word.isEmpty { set.insert(w.word.lowercased()) }
            if !w.lemma.isEmpty, !w.lemma.contains(" ") { set.insert(w.lemma.lowercased()) }
        }
        return set
    }

    /// The saved entry for this exact word in this exact sentence, if any.
    func entry(for request: LookupRequest) -> SavedWord? {
        let w = request.word.lowercased()
        return first { $0.word.lowercased() == w && $0.sentence == request.sentence }
    }
}
