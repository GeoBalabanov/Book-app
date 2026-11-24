import CryptoKit
import Foundation
import SwiftData

/// A word the reader long-pressed, with the sentence it appears in.
struct LookupRequest: Identifiable, Hashable {
    let word: String          // exactly as printed
    let sentence: String      // the full sentence
    let offset: Int           // UTF-16 index of `word` inside `sentence`
    var bookTitle: String = ""
    var bookID: String = ""
    var id: String { "\(word)|\(offset)|\(sentence)" }
}

struct LookupResult: Codable, Equatable {
    var word: String
    var lemma: String                 // English base form
    var partOfSpeech: String
    var translation: String           // Bulgarian for the word as used in this sentence
    var dictionaryTranslation: String // Bulgarian for the lemma, when it differs from the word
    var sentenceTranslation: String   // Bulgarian for the whole sentence
    var provider: String              // id of the service that answered
}

/// The one interface the UI talks to. To add a provider, implement this and
/// return it from `TranslationProviders.current`.
protocol TranslationService {
    var id: String { get }
    /// Shown under results, e.g. "Translated by DeepL".
    var attribution: String { get }
    func translate(_ request: LookupRequest) async throws -> LookupResult
}

struct TranslationError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum TranslationProviders {
    /// The DeepL key from Secrets.xcconfig (exposed through Info.plist), if one is set.
    static var deepLKey: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "DeepLAPIKey") as? String else { return nil }
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty || key.hasPrefix("$(") || key.hasPrefix("your-deepl-key") { return nil }
        return key
    }

    /// DeepL when a key is configured, otherwise clearly labelled demo translations.
    static var current: TranslationService {
        if let key = deepLKey { return DeepLTranslationService(apiKey: key) }
        return DemoTranslationService()
    }
}

/// Cached translation, keyed by provider + word + offset + sentence, so the
/// same lookup is never sent twice.
@Model
final class CachedTranslation {
    @Attribute(.unique) var key: String
    var provider: String
    var result: Data
    var createdAt: Date

    init(key: String, provider: String, result: Data) {
        self.key = key
        self.provider = provider
        self.result = result
        self.createdAt = .now
    }
}

@MainActor
enum Translator {
    static func cacheKey(provider: String, _ req: LookupRequest) -> String {
        let raw = "\(req.word.lowercased())|\(req.offset)|\(req.sentence)"
        let digest = SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
        return "\(provider)-\(digest)"
    }

    static func cached(_ req: LookupRequest, provider: String, in context: ModelContext) -> LookupResult? {
        let key = cacheKey(provider: provider, req)
        let found = try? context.fetch(FetchDescriptor<CachedTranslation>(predicate: #Predicate { $0.key == key }))
        return found?.first.flatMap { try? JSONDecoder().decode(LookupResult.self, from: $0.result) }
    }

    /// Look a word up, from the cache when possible.
    static func lookup(_ req: LookupRequest, in context: ModelContext,
                       service: TranslationService = TranslationProviders.current) async throws -> LookupResult {
        if let hit = cached(req, provider: service.id, in: context) { return hit }
        var result = try await service.translate(req)
        result.word = req.word
        result.provider = service.id
        if let data = try? JSONEncoder().encode(result) {
            let key = cacheKey(provider: service.id, req)
            // Another lookup may have stored it while this one was in flight.
            if cached(req, provider: service.id, in: context) == nil {
                context.insert(CachedTranslation(key: key, provider: service.id, result: data))
                try? context.save()
            }
        }
        return result
    }
}
