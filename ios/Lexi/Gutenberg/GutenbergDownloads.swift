import Foundation
import SwiftData
import SwiftUI
import UIKit

/// Downloads Gutenberg EPUBs into the Library, and covers for display.
@Observable
@MainActor
final class GutenbergDownloads {
    static let shared = GutenbergDownloads()

    enum State: Equatable { case downloading, failed(String) }
    private(set) var states: [Int: State] = [:]

    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 20
        c.timeoutIntervalForResource = 180
        c.httpAdditionalHeaders = ["User-Agent": "Lexi/1.0 (iOS reading app)"]
        c.urlCache = URLCache(memoryCapacity: 20 << 20, diskCapacity: 200 << 20)
        c.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: c)
    }()

    static func libraryID(for gutenbergID: Int) -> String { "gutenberg-\(gutenbergID)" }

    /// Downloads the EPUB and imports it. Returns the new (or existing) Book.
    @discardableResult
    func get(_ book: CatalogBook, into context: ModelContext) async -> Book? {
        let id = Self.libraryID(for: book.id)
        if let existing = try? context.fetch(FetchDescriptor<Book>(predicate: #Predicate { $0.id == id })).first {
            return existing
        }
        guard states[book.id] != .downloading else { return nil }
        states[book.id] = .downloading
        do {
            let file = try await Self.downloadEPUB(book)
            defer { try? FileManager.default.removeItem(at: file) }
            let imported = try LibraryStore.importEpub(at: file, into: context, id: id)
            imported.gutenbergID = book.id
            try? context.save()
            states[book.id] = nil
            return imported
        } catch {
            states[book.id] = .failed((error as? LocalizedError)?.errorDescription ?? "The download failed. Try again.")
            return nil
        }
    }

    func clearError(_ id: Int) { if case .failed = states[id] { states[id] = nil } }

    private struct DownloadError: LocalizedError {
        var errorDescription: String? { "Couldn’t download this book from Project Gutenberg. Check your connection and try again." }
    }

    /// Tries gutenberg.org, then the mirror; accepts only real ZIP (EPUB) files.
    nonisolated private static func downloadEPUB(_ book: CatalogBook) async throws -> URL {
        for url in book.epubURLs {
            guard let (tmp, response) = try? await session.download(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200 else { continue }
            let handle = try? FileHandle(forReadingFrom: tmp)
            let magic = try? handle?.read(upToCount: 2)
            try? handle?.close()
            guard magic == Data("PK".utf8) else { continue }
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent("pg\(book.id)-\(UUID().uuidString).epub")
            try FileManager.default.moveItem(at: tmp, to: dest)
            return dest
        }
        throw DownloadError()
    }

    // MARK: Covers

    private static let coverCache = NSCache<NSNumber, UIImage>()
    private static var missingCovers = Set<Int>()

    /// The book's cover, from cache, gutenberg.org or the mirror; nil if it has none.
    static func cover(for book: CatalogBook) async -> UIImage? {
        if let img = coverCache.object(forKey: book.id as NSNumber) { return img }
        if missingCovers.contains(book.id) { return nil }
        for url in book.coverURLs {
            guard let (data, response) = try? await session.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let img = UIImage(data: data) else { continue }
            coverCache.setObject(img, forKey: book.id as NSNumber)
            return img
        }
        missingCovers.insert(book.id)
        return nil
    }
}

/// A Gutenberg cover that loads on appear, with a generated cloth cover as
/// placeholder and fallback. Sits on the bottom edge of a 2:3 slot.
struct RemoteCover: View {
    let book: CatalogBook
    var showsTitleOnPlaceholder = true
    @State private var image: UIImage?

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 2, bottomLeadingRadius: 2, bottomTrailingRadius: 4, topTrailingRadius: 4)
    }

    var body: some View {
        Color.clear
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .overlay(alignment: .bottom) {
                if let image {
                    Image(uiImage: image).resizable().aspectRatio(contentMode: .fit)
                        .clipShape(shape).modifier(CoverShadow())
                        .transition(.opacity)
                } else {
                    GeneratedCover(title: book.shortTitle, author: book.author, showsText: showsTitleOnPlaceholder)
                }
            }
            .task(id: book.id) {
                if let img = await GutenbergDownloads.cover(for: book) {
                    withAnimation(.easeOut(duration: 0.2)) { image = img }
                }
            }
            .accessibilityLabel("\(book.shortTitle) by \(book.author)")
    }
}

/// Muted cloth cover with the title, for books without a cover image.
struct GeneratedCover: View {
    let title: String
    let author: String
    var showsText = true

    static let cloth: [Color] = [
        Color(red: 0.23, green: 0.21, blue: 0.19), Color(red: 0.18, green: 0.24, blue: 0.27),
        Color(red: 0.29, green: 0.18, blue: 0.18), Color(red: 0.19, green: 0.25, blue: 0.20),
        Color(red: 0.25, green: 0.22, blue: 0.30), Color(red: 0.32, green: 0.26, blue: 0.18),
    ]

    /// Stable across launches (String.hashValue is randomized per process).
    static func color(for title: String) -> Color {
        let sum = title.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xffff }
        return cloth[sum % cloth.count]
    }

    var body: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 2, bottomLeadingRadius: 2, bottomTrailingRadius: 4, topTrailingRadius: 4)
        GeometryReader { g in
            VStack(alignment: .leading) {
                if showsText {
                    Text(title).font(.system(size: max(9, g.size.width * 0.12), weight: .semibold, design: .serif))
                        .lineLimit(4).minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                    Text(author.uppercased()).font(.system(size: max(6, g.size.width * 0.065), weight: .medium))
                        .tracking(0.5).opacity(0.7).lineLimit(2)
                }
            }
            .foregroundStyle(Color(red: 0.96, green: 0.94, blue: 0.90))
            .padding(.vertical, g.size.height * 0.08)
            .padding(.horizontal, g.size.width * 0.1)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(Self.color(for: title), in: shape)
            .modifier(CoverShadow())
        }
    }
}
