import Foundation
import SwiftData
import ZIPFoundation

/// Imports, stores and removes books. EPUBs are unzipped once on import so the
/// reader can serve chapters and images straight from disk.
@MainActor
enum LibraryStore {
    static let sampleID = "sample-war-of-the-worlds"
    private static let sampleRemovedKey = "lexi.sampleRemoved"

    static var booksDirectory: URL {
        let dir = URL.applicationSupportDirectory.appendingPathComponent("Books", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func folderURL(for book: Book) -> URL { booksDirectory.appendingPathComponent(book.folder, isDirectory: true) }

    /// Adds the bundled sample on first launch (unless the reader removed it).
    static func ensureSample(in context: ModelContext) {
        if UserDefaults.standard.bool(forKey: sampleRemovedKey) { return }
        let id = sampleID
        let existing = try? context.fetch(FetchDescriptor<Book>(predicate: #Predicate { $0.id == id }))
        if let book = existing?.first {
            // Re-extract if the files went missing (e.g. a reinstall restored the store only).
            if FileManager.default.fileExists(atPath: folderURL(for: book).path) { return }
            context.delete(book)
        }
        guard let url = Bundle.main.url(forResource: "war-of-the-worlds", withExtension: "epub") else { return }
        do {
            _ = try importEpub(at: url, into: context, id: id, isSample: true, addedAt: .distantPast)
        } catch {
            print("Sample book unavailable: \(error)")
        }
    }

    /// Unzip, parse and store an EPUB. Throws `EpubError` for files that aren't usable books.
    @discardableResult
    static func importEpub(at url: URL, into context: ModelContext, id: String = UUID().uuidString,
                           isSample: Bool = false, addedAt: Date = .now) throws -> Book {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let folder = id
        let dest = booksDirectory.appendingPathComponent(folder, isDirectory: true)
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.unzipItem(at: url, to: dest)
        } catch {
            try? FileManager.default.removeItem(at: dest)
            throw EpubError.notZip
        }

        do {
            let parser = EpubParser(root: dest)
            let pkg = try parser.parse()
            let cover = pkg.coverPath.flatMap { try? parser.data($0) }
            let book = Book(id: id, title: pkg.title, author: pkg.author, coverData: cover, folder: folder,
                            spine: pkg.spine, textLengths: parser.textLengths(pkg.spine), toc: pkg.toc,
                            isSample: isSample, addedAt: addedAt)
            context.insert(book)
            try context.save()
            return book
        } catch {
            try? FileManager.default.removeItem(at: dest)
            throw error
        }
    }

    static func remove(_ book: Book, from context: ModelContext) {
        if book.isSample { UserDefaults.standard.set(true, forKey: sampleRemovedKey) }
        try? FileManager.default.removeItem(at: folderURL(for: book))
        context.delete(book)
        try? context.save()
    }
}
