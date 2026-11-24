import Foundation
import SwiftUI

/// One English Project Gutenberg book from the bundled catalogue.
struct CatalogBook: Identifiable, Hashable {
    let id: Int
    let title: String
    let author: String
    let categories: [Int]   // indexes into GutenbergCatalog.categories
    let rank: Double        // lower = more prominent (curated popular list first)

    /// "Frankenstein; or, The modern Prometheus" → "Frankenstein"
    var shortTitle: String {
        for sep in ["; ", ": "] {
            if let r = title.range(of: sep), title.distance(from: title.startIndex, to: r.lowerBound) >= 3 {
                return String(title[..<r.lowerBound])
            }
        }
        return title
    }

    var isPopular: Bool { rank < 2 }

    /// Cover images: gutenberg.org first, then the pglaf mirror.
    var coverURLs: [URL] {
        [URL(string: "https://www.gutenberg.org/cache/epub/\(id)/pg\(id).cover.medium.jpg")!,
         URL(string: "https://gutenberg.pglaf.org/cache/epub/\(id)/pg\(id).cover.medium.jpg")!]
    }

    /// EPUB 3 with images: gutenberg.org first, then the pglaf mirror.
    var epubURLs: [URL] {
        [URL(string: "https://www.gutenberg.org/ebooks/\(id).epub3.images")!,
         URL(string: "https://gutenberg.pglaf.org/cache/epub/\(id)/pg\(id)-images-3.epub")!]
    }

    var pageURL: URL { URL(string: "https://www.gutenberg.org/ebooks/\(id)")! }
}

/// The bundled Project Gutenberg catalogue (English texts), built by
/// ios/Tools/build_catalog.py from Gutenberg's own pg_catalog.csv. Search runs
/// locally, so it is instant and works offline; only covers and EPUBs are
/// downloaded, on demand.
@Observable
@MainActor
final class GutenbergCatalog {
    static let shared = GutenbergCatalog()

    private(set) var books: [CatalogBook] = []
    private(set) var categories: [String] = []
    private(set) var isLoaded = false
    private var byID: [Int: CatalogBook] = [:]
    /// Lowercased, diacritic-folded "title author" per book, same order as `books`.
    private var keys: [String] = []
    private var loading: Task<Void, Never>?

    /// Loads the catalogue once, off the main thread.
    func load() async {
        if isLoaded { return }
        if let loading { await loading.value; return }
        let task = Task {
            let parsed = await Task.detached(priority: .userInitiated) { Self.parse() }.value
            categories = parsed.categories
            books = parsed.books
            keys = parsed.keys
            byID = Dictionary(uniqueKeysWithValues: parsed.books.map { ($0.id, $0) })
            isLoaded = true
        }
        loading = task
        await task.value
    }

    func book(id: Int) -> CatalogBook? { byID[id] }

    func categoryIndex(_ name: String) -> Int? { categories.firstIndex(of: name) }

    /// Books in any of these categories, most prominent first.
    func shelf(_ names: [String], excluding: Set<Int> = [], limit: Int = 24) -> [CatalogBook] {
        let wanted = Set(names.compactMap(categoryIndex))
        var out: [CatalogBook] = []
        for b in books where !excluding.contains(b.id) && b.categories.contains(where: wanted.contains) {
            out.append(b)
            if out.count == limit { break }
        }
        return out
    }

    func popular(excluding: Set<Int> = [], limit: Int = 24) -> [CatalogBook] {
        Array(books.lazy.filter { $0.isPopular && !excluding.contains($0.id) }.prefix(limit))
    }

    /// Every word of the query must appear in the title or author. Title
    /// matches rank above author matches; then the catalogue's own ranking.
    nonisolated static func search(_ query: String, books: [CatalogBook], keys: [String], limit: Int = 80) -> [CatalogBook] {
        let tokens = fold(query).split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return [] }
        let phrase = tokens.joined(separator: " ")
        var scored: [(Int, Int)] = []   // (score, index)
        for (i, key) in keys.enumerated() where tokens.allSatisfy({ key.contains($0) }) {
            let title = fold(books[i].title)
            let author = fold(books[i].author)
            let score: Int
            if title.hasPrefix(phrase) { score = 0 }
            else if title.contains(phrase) { score = 1 }
            // Every word in the title, or the words split between title and author
            // ("austen pride"): equally good, so popularity decides.
            else if tokens.allSatisfy({ title.contains($0) })
                        || (tokens.contains { author.contains($0) } && tokens.allSatisfy { title.contains($0) || author.contains($0) }
                            && tokens.contains { title.contains($0) }) { score = 2 }
            else { score = 3 }
            scored.append((score, i))
        }
        scored.sort { a, b in
            if a.0 != b.0 { return a.0 < b.0 }
            let ba = books[a.1], bb = books[b.1]
            return ba.rank != bb.rank ? ba.rank < bb.rank : ba.id < bb.id
        }
        return scored.prefix(limit).map { books[$0.1] }
    }

    /// Runs `search` off the main thread.
    func search(_ query: String) async -> [CatalogBook] {
        await load()
        let books = books, keys = keys
        return await Task.detached(priority: .userInitiated) { Self.search(query, books: books, keys: keys) }.value
    }

    nonisolated static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: " +", with: " ", options: .regularExpression)
    }

    private struct Parsed: Sendable {
        var categories: [String] = []
        var books: [CatalogBook] = []
        var keys: [String] = []
    }

    nonisolated private static func parse() -> Parsed {
        guard let url = Bundle.main.url(forResource: "gutenberg-catalog", withExtension: "bin"),
              let raw = try? Data(contentsOf: url),
              let data = try? (raw as NSData).decompressed(using: .zlib) as Data,
              let text = String(data: data, encoding: .utf8) else { return Parsed() }
        var out = Parsed()
        var first = true
        text.enumerateLines { line, _ in
            if first {
                out.categories = line.components(separatedBy: "\t")
                first = false
                return
            }
            let f = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard f.count == 5, let id = Int(f[0]) else { return }
            let cats = f[3].split(separator: ",").compactMap { Int($0) }
            let book = CatalogBook(id: id, title: String(f[1]), author: String(f[2]), categories: cats, rank: Double(f[4]) ?? 3)
            out.books.append(book)
            out.keys.append(fold("\(book.title) \(book.author)"))
        }
        return out
    }
}

extension CatalogBook: Sendable {}
