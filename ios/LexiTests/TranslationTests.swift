import SwiftData
import XCTest
@testable import Lexi

/// Ported from web/tests/deepl.test.mjs.
final class DeepLCoreTests: XCTestCase {
    func testMarkSentenceWrapsWordAtOffsetAndEscapesXML() {
        XCTAssertEqual(DeepLCore.markSentence("Tom & the bank by the bank.", word: "bank", offset: 22), "Tom &amp; the bank by the <w>bank</w>.")
        XCTAssertEqual(DeepLCore.markSentence("He ran home.", word: "ran", offset: 99), "He <w>ran</w> home.")
        XCTAssertNil(DeepLCore.markSentence("Nothing here.", word: "absent", offset: 0))
    }

    func testParseTaggedExtractsWordAndCleanSentence() {
        let r = DeepLCore.parseTagged("Той <w>изтича</w> към къщи &amp; спря.")
        XCTAssertEqual(r.word, "изтича")
        XCTAssertEqual(r.sentence, "Той изтича към къщи & спря.")
        XCTAssertNil(DeepLCore.parseTagged("Без таг.").word)
    }

    func testHostPicksFreeEndpointForFxKeys() {
        XCTAssertEqual(DeepLCore.host(for: "abc:fx").absoluteString, "https://api-free.deepl.com")
        XCTAssertEqual(DeepLCore.host(for: "abc").absoluteString, "https://api.deepl.com")
    }

    func testUTF16OffsetsWithEmojiAndQuotes() {
        // Offsets come from JavaScript, so they count UTF-16 units.
        XCTAssertEqual(DeepLCore.markSentence("“Ah 😀” she sighed.", word: "sighed", offset: 12), "“Ah 😀” she <w>sighed</w>.")
    }
}

final class WordAnalyzerTests: XCTestCase {
    func testLemmaAndPartOfSpeech() {
        let a = WordAnalyzer.analyze(sentence: "The Martians were watching us closely.", word: "watching", offset: 21)
        XCTAssertEqual(a.lemma, "watch")
        XCTAssertEqual(a.partOfSpeech, "verb")
        let n = WordAnalyzer.analyze(sentence: "They studied the creatures in the water.", word: "creatures", offset: 17)
        XCTAssertEqual(n.lemma, "creature")
        XCTAssertEqual(n.partOfSpeech, "noun, plural")
    }
}

@MainActor
final class TranslationCacheTests: XCTestCase {
    func testCacheKeyDependsOnProviderWordOffsetAndSentence() {
        let a = LookupRequest(word: "Bank", sentence: "The bank.", offset: 4)
        let b = LookupRequest(word: "bank", sentence: "The bank.", offset: 4)
        XCTAssertEqual(Translator.cacheKey(provider: "deepl", a), Translator.cacheKey(provider: "deepl", b))
        XCTAssertNotEqual(Translator.cacheKey(provider: "deepl", a), Translator.cacheKey(provider: "demo", a))
        XCTAssertNotEqual(Translator.cacheKey(provider: "deepl", a),
                          Translator.cacheKey(provider: "deepl", LookupRequest(word: "bank", sentence: "The bank!", offset: 4)))
    }
}

/// Counts calls so tests can check the cache prevents repeat requests.
private final class CountingService: TranslationService {
    var calls = 0
    var id: String { "counting" }
    var attribution: String { "" }
    func translate(_ req: LookupRequest) async throws -> LookupResult {
        calls += 1
        return LookupResult(word: req.word, lemma: req.word, partOfSpeech: "noun", translation: "превод",
                            dictionaryTranslation: "", sentenceTranslation: "изречение", provider: id)
    }
}

@MainActor
final class TranslationCacheLookupTests: XCTestCase {
    func testSameWordAndSentenceIsTranslatedOnce() async throws {
        let container = try ModelContainer(for: CachedTranslation.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let service = CountingService()
        let req = LookupRequest(word: "bank", sentence: "He sat on the bank.", offset: 14)

        let first = try await Translator.lookup(req, in: context, service: service)
        let second = try await Translator.lookup(req, in: context, service: service)
        XCTAssertEqual(service.calls, 1)
        XCTAssertEqual(first, second)

        // A different sentence is a different lookup.
        _ = try await Translator.lookup(LookupRequest(word: "bank", sentence: "The bank was closed.", offset: 4), in: context, service: service)
        XCTAssertEqual(service.calls, 2)
    }
}
