import Foundation
import SwiftData

/// A book in the library. The unzipped EPUB lives in Application Support/Books/<folder>.
@Model
final class Book {
    @Attribute(.unique) var id: String
    var title: String
    var author: String
    @Attribute(.externalStorage) var coverData: Data?
    var addedAt: Date
    var lastOpenedAt: Date?
    var isSample: Bool

    /// Where the unzipped EPUB is stored, relative to the books directory.
    var folder: String
    var spine: [String]
    var textLengths: [Int]
    var tocJSON: Data

    // Reading position
    var hasLocation: Bool
    var locationChapter: Int
    var locationFraction: Double
    var progress: Double          // 0...1 over the whole book
    var chapterLabel: String

    /// Project Gutenberg ebook number, for books from the catalogue (and the sample).
    var gutenbergID: Int? = nil

    init(id: String, title: String, author: String, coverData: Data?, folder: String,
         spine: [String], textLengths: [Int], toc: [TocEntry], isSample: Bool, addedAt: Date = .now) {
        self.id = id
        self.title = title
        self.author = author
        self.coverData = coverData
        self.addedAt = addedAt
        self.lastOpenedAt = nil
        self.isSample = isSample
        self.folder = folder
        self.spine = spine
        self.textLengths = textLengths
        self.tocJSON = (try? JSONEncoder().encode(toc)) ?? Data("[]".utf8)
        self.hasLocation = false
        self.locationChapter = 0
        self.locationFraction = 0
        self.progress = 0
        self.chapterLabel = ""
    }

    var toc: [TocEntry] { (try? JSONDecoder().decode([TocEntry].self, from: tocJSON)) ?? [] }

    /// Most recent activity, used to order the library.
    var recency: Date { lastOpenedAt ?? addedAt }

    var isStarted: Bool { progress > 0 || hasLocation }
}
