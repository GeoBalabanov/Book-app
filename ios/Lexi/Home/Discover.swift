import SwiftData
import SwiftUI

/// App-wide navigation: the selected tab and the book open in the reader.
@Observable
@MainActor
final class AppRouter {
    enum Tab: Hashable { case home, library, vocabulary, flashcards, search }
    var tab: Tab = .home
    var openBook: Book?
}

/// A named collection of catalogue books (a Top Picks card or a genre).
struct Shelf: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let books: [CatalogBook]
}

/// Builds the Top Picks shelves from the catalogue and the reader's library.
@MainActor
enum Shelves {
    struct Genre {
        let id: String, title: String, subtitle: String, symbol: String, categories: [String]
    }

    static let genres: [Genre] = [
        .init(id: "fiction", title: "Fiction & Literature", subtitle: "Explore the best-loved classics.", symbol: "book",
              categories: ["Classics of Literature", "Novels"]),
        .init(id: "scifi", title: "Science Fiction & Fantasy", subtitle: "Time machines, Martians and other worlds.", symbol: "sparkles",
              categories: ["Science-Fiction & Fantasy"]),
        .init(id: "mystery", title: "Mystery & Crime", subtitle: "Detectives, thieves and locked rooms.", symbol: "magnifyingglass",
              categories: ["Crime, Thrillers and Mystery"]),
        .init(id: "adventure", title: "Adventure", subtitle: "Voyages, islands and daring escapes.", symbol: "map",
              categories: ["Adventure"]),
        .init(id: "romance", title: "Romance", subtitle: "Courtships, misunderstandings and letters.", symbol: "heart",
              categories: ["Romance"]),
        .init(id: "philosophy", title: "Philosophy & Ideas", subtitle: "From Plato to Nietzsche.", symbol: "lightbulb",
              categories: ["Philosophy & Ethics", "Politics"]),
        .init(id: "poetry", title: "Poetry & Plays", subtitle: "Verse and drama, from Homer to Shaw.", symbol: "theatermasks",
              categories: ["Poetry", "Plays/Films/Dramas"]),
        .init(id: "young", title: "Children & Young Adult", subtitle: "Wonderland, Oz and Neverland.", symbol: "balloon",
              categories: ["Children & Young Adult Reading"]),
    ]

    /// Categories too broad to say much about what someone likes.
    private static let broad: Set<String> = ["Novels", "Classics of Literature", "British Literature", "American Literature"]

    static func genre(_ g: Genre, catalog: GutenbergCatalog, owned: Set<Int>) -> Shelf {
        Shelf(id: g.id, title: g.title, subtitle: g.subtitle, symbol: g.symbol,
              books: catalog.shelf(g.categories, excluding: owned, limit: 60))
    }

    /// "Books you might like": the genres of books you've opened, most recent first.
    static func suggestions(library: [Book], catalog: GutenbergCatalog) -> Shelf {
        let owned = Set(library.compactMap(\.gutenbergID))
        let read = library.filter { $0.gutenbergID != nil }.sorted { $0.recency > $1.recency }
        var names: [String] = []
        for book in read {
            guard let id = book.gutenbergID, let entry = catalog.book(id: id) else { continue }
            for c in entry.categories where !broad.contains(catalog.categories[c]) && !names.contains(catalog.categories[c]) {
                names.append(catalog.categories[c])
            }
        }
        let books = names.isEmpty ? [] : catalog.shelf(names, excluding: owned, limit: 60)
        return Shelf(id: "suggested", title: "Books you might like", subtitle: "Suggestions based on your reading activity.",
                     symbol: "star", books: books.isEmpty ? catalog.popular(excluding: owned, limit: 60) : books)
    }
}

// MARK: - Book detail

/// A catalogue book: cover, title, author, genres, and Get / Read.
struct BookDetailView: View {
    let book: CatalogBook
    @State private var catalog = GutenbergCatalog.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                RemoteCover(book: book)
                    .frame(width: 190)
                    .padding(.top, 12)
                    .padding(.bottom, 10)
                Text(book.title)
                    .font(.system(size: 26, weight: .bold, design: .serif))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if !book.author.isEmpty {
                    Text(book.author).font(.title3).foregroundStyle(.secondary)
                }
                GetButton(book: book, style: .large)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 0) {
                    infoRow("Price", "Free")
                    Divider()
                    infoRow("Source", "Project Gutenberg #\(book.id)")
                    if !genres.isEmpty {
                        Divider()
                        infoRow("Genre", genres.joined(separator: ", "))
                    }
                }
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.top, 18)

                Link(destination: book.pageURL) {
                    Label("View on Project Gutenberg", systemImage: "safari")
                        .font(.subheadline)
                }
                .padding(.top, 6)
                Text("Public-domain ebook from Project Gutenberg. Downloads come from gutenberg.org or its pglaf.org mirror.")
                    .font(.footnote).foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private var genres: [String] {
        book.categories.compactMap { $0 < catalog.categories.count ? catalog.categories[$0] : nil }
            .filter { !["British Literature", "American Literature"].contains($0) }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

/// "Get" → downloading → "Read". Opens the book once it's in the Library.
struct GetButton: View {
    enum Style { case large, compact }
    let book: CatalogBook
    var style: Style = .compact

    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Query private var library: [Book]
    @State private var downloads = GutenbergDownloads.shared

    private var owned: Book? { library.first { $0.gutenbergID == book.id } }

    var body: some View {
        VStack(spacing: 8) {
            if let owned {
                button("Read") { router.openBook = owned }
            } else if downloads.states[book.id] == .downloading {
                ProgressView()
                    .frame(width: style == .large ? 200 : 64, height: style == .large ? 50 : 30)
                    .accessibilityLabel("Downloading")
            } else {
                button("Get") {
                    downloads.clearError(book.id)
                    Task { await downloads.get(book, into: context) }
                }
            }
            if style == .large, case .failed(let message) = downloads.states[book.id] {
                Text(message).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
            }
        }
    }

    @ViewBuilder private func button(_ title: String, action: @escaping () -> Void) -> some View {
        switch style {
        case .large:
            Button(title, action: action).buttonStyle(InkButtonStyle()).frame(minWidth: 200)
        case .compact:
            Button(action: action) {
                Text(title.uppercased())
                    .font(.system(size: 14, weight: .bold))
                    .padding(.horizontal, 16)
                    .frame(height: 30)
                    .background(Color(.tertiarySystemFill), in: Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
        }
    }
}

// MARK: - Shelf

/// All books on a shelf, as a cover grid.
struct ShelfView: View {
    let shelf: Shelf

    var body: some View {
        ScrollView {
            if !shelf.subtitle.isEmpty {
                Text(shelf.subtitle)
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104, maximum: 160), spacing: 18, alignment: .bottom)], spacing: 22) {
                ForEach(shelf.books) { book in
                    NavigationLink(value: book) {
                        VStack(alignment: .leading, spacing: 6) {
                            RemoteCover(book: book)
                            Text(book.shortTitle).font(.footnote.weight(.semibold)).lineLimit(2)
                            Text(book.author).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .frame(maxHeight: .infinity, alignment: .top)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .navigationTitle(shelf.title)
    }
}
