import Foundation

/// Pure helpers for the DeepL provider, ported from web/js/translation/deepl-core.js.
/// Offsets are UTF-16 indices, as reported by the reader page.
enum DeepLCore {
    /// Wrap the word at `offset` in <w>…</w>, escaping the rest for XML tag handling.
    static func markSentence(_ sentence: String, word: String, offset: Int?) -> String? {
        let s = sentence as NSString
        let len = (word as NSString).length
        var start = NSNotFound
        if let offset, offset >= 0, offset + len <= s.length, s.substring(with: NSRange(location: offset, length: len)) == word {
            start = offset
        } else {
            start = s.range(of: word).location
        }
        guard start != NSNotFound else { return nil }
        let before = s.substring(to: start)
        let after = s.substring(from: start + len)
        return "\(escape(before))<w>\(escape(word))</w>\(escape(after))"
    }

    /// Split DeepL's tagged output into the in-context word translation and the
    /// plain sentence translation. `word` is nil when the tag was dropped or empty.
    static func parseTagged(_ text: String) -> (word: String?, sentence: String) {
        var word: String?
        if let open = text.range(of: "<w>"), let close = text.range(of: "</w>", range: open.upperBound..<text.endIndex) {
            let inner = unescape(String(text[open.upperBound..<close.lowerBound]))
                .replacingOccurrences(of: "[.,;:!?\"“”«»]+$", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            word = inner.isEmpty ? nil : inner
        }
        let sentence = unescape(text.replacingOccurrences(of: "</?w>", with: "", options: .regularExpression))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (word, sentence)
    }

    /// DeepL Free keys end in ":fx" and use a different host.
    static func host(for key: String) -> URL {
        key.trimmingCharacters(in: .whitespaces).hasSuffix(":fx")
            ? URL(string: "https://api-free.deepl.com")! : URL(string: "https://api.deepl.com")!
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}

/// DeepL provider, ported from web/js/translation/deepl.js.
///
/// One request translates the sentence with the word wrapped in <w>…</w>
/// (tag_handling=xml): the tagged span is the in-context word translation and
/// the whole output is the sentence translation. If DeepL drops the tag, the
/// word is translated alone with `context=<sentence>`. Lemma and part of speech
/// come from NaturalLanguage on device.
struct DeepLTranslationService: TranslationService {
    let apiKey: String
    var session: URLSession = .shared

    var id: String { "deepl" }
    var attribution: String { "Translated by DeepL" }

    func translate(_ req: LookupRequest) async throws -> LookupResult {
        var wordTr: String?
        var sentenceTr = ""
        if let marked = DeepLCore.markSentence(req.sentence, word: req.word, offset: req.offset) {
            let context = req.bookTitle.isEmpty ? nil : "From the book \"\(req.bookTitle)\"."
            let out = try await call(texts: [marked], tagHandling: "xml", context: context)
            (wordTr, sentenceTr) = DeepLCore.parseTagged(out.first ?? "")
        } else {
            sentenceTr = try await call(texts: [req.sentence]).first ?? ""
        }

        let analysis = WordAnalyzer.analyze(sentence: req.sentence, word: req.word, offset: req.offset)
        let lemma = analysis.lemma
        var extra: [String] = []
        if wordTr == nil { extra.append(req.word) }
        if lemma.lowercased() != req.word.lowercased() { extra.append(lemma) }
        var dict = ""
        if !extra.isEmpty {
            var outs = try await call(texts: extra, context: req.sentence)
            if wordTr == nil, !outs.isEmpty { wordTr = outs.removeFirst() }
            dict = outs.first ?? ""
        }

        return LookupResult(word: req.word, lemma: lemma, partOfSpeech: analysis.partOfSpeech,
                            translation: wordTr ?? "", dictionaryTranslation: dict,
                            sentenceTranslation: sentenceTr, provider: id)
    }

    private struct Response: Decodable {
        struct Item: Decodable { let text: String }
        let translations: [Item]
    }

    private func call(texts: [String], tagHandling: String? = nil, context: String? = nil) async throws -> [String] {
        var body: [String: Any] = ["text": texts, "source_lang": "EN", "target_lang": "BG"]
        if let tagHandling { body["tag_handling"] = tagHandling }
        if let context { body["context"] = context }

        var request = URLRequest(url: DeepLCore.host(for: apiKey).appendingPathComponent("v2/translate"))
        request.httpMethod = "POST"
        request.setValue("DeepL-Auth-Key \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 20

        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw TranslationError(message: "Couldn’t reach DeepL. Check your connection and try again.")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            switch status {
            case 403: throw TranslationError(message: "DeepL rejected the API key. Check ios/Config/Secrets.xcconfig.")
            case 456: throw TranslationError(message: "Your DeepL quota for this month is used up.")
            case 429: throw TranslationError(message: "Too many DeepL requests. Wait a moment and try again.")
            default: throw TranslationError(message: "DeepL request failed (\(status)).")
            }
        }
        return try JSONDecoder().decode(Response.self, from: data).translations.map(\.text)
    }
}

/// Offline stand-in used when no DeepL key is configured. Results are clearly
/// marked as demo text. Ported from web/js/translation/mock.js.
struct DemoTranslationService: TranslationService {
    var id: String { "demo" }
    var attribution: String { "Demo translation · add a DeepL key for real ones" }

    func translate(_ req: LookupRequest) async throws -> LookupResult {
        try await Task.sleep(for: .milliseconds(400))
        let w = req.word.lowercased()
        let analysis = WordAnalyzer.analyze(sentence: req.sentence, word: req.word, offset: req.offset)
        return LookupResult(word: req.word, lemma: analysis.lemma, partOfSpeech: analysis.partOfSpeech,
                            translation: "«\(w)» (демо)",
                            dictionaryTranslation: analysis.lemma != w ? "\(analysis.lemma) (речник)" : "",
                            sentenceTranslation: "[Демо превод] \(req.sentence)", provider: id)
    }
}
