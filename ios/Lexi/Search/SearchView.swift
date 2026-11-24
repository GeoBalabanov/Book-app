import SwiftData
import SwiftUI

/// Search tab: instant search of the bundled Project Gutenberg catalogue
/// (62,000 English books), with genres and popular classics when empty.
struct SearchView: View {
    @State private var catalog = GutenbergCatalog.shared
    @State private var query = ""
    @State private var results: [CatalogBook] = []
    @State private var searching = false
    @Query private var library: [Book]

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            List {
                if trimmed.isEmpty {
                    browse
                } else if results.isEmpty && !searching {
                    ContentUnavailableView.search(text: trimmed)
                        .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(results) { book in
                            NavigationLink(value: book) { BookRow(book: book) }
                        }
                    } footer: {
                        if results.count == 80 { Text("Showing the first 80 matches. Add a word to narrow the search.") }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Search")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Books and authors")
            .autocorrectionDisabled()
            .navigationDestination(for: CatalogBook.self) { BookDetailView(book: $0) }
            .navigationDestination(for: Shelf.self) { ShelfView(shelf: $0) }
            .task(id: trimmed) {
                guard !trimmed.isEmpty else { results = []; return }
                searching = true
                try? await Task.sleep(for: .milliseconds(150))   // debounce typing
                guard !Task.isCancelled else { return }
                let found = await catalog.search(trimmed)
                guard !Task.isCancelled else { return }
                results = found
                searching = false
            }
        }
        .task { await catalog.load() }
    }

    @ViewBuilder private var browse: some View {
        let owned = Set(library.compactMap(\.gutenbergID))
        Section {
            ForEach(Shelves.genres, id: \.id) { g in
                NavigationLink(value: Shelves.genre(g, catalog: catalog, owned: owned)) {
                    Label(g.title, systemImage: g.symbol)
                        .font(.system(size: 18))
                        .padding(.vertical, 4)
                }
                .disabled(!catalog.isLoaded)
            }
        } header: {
            Text("Browse Genres").font(.system(size: 22, weight: .bold, design: .serif)).foregroundStyle(Color(.label)).textCase(nil)
        }
        Section {
            ForEach(catalog.popular(excluding: owned, limit: 12)) { book in
                NavigationLink(value: book) { BookRow(book: book) }
            }
        } header: {
            Text("Popular Classics").font(.system(size: 22, weight: .bold, design: .serif)).foregroundStyle(Color(.label)).textCase(nil)
        } footer: {
            Text("Free public-domain ebooks from Project Gutenberg.")
        }
    }
}

/// Cover, title and author, with Get / Read on the right.
struct BookRow: View {
    let book: CatalogBook

    var body: some View {
        HStack(spacing: 14) {
            RemoteCover(book: book, showsTitleOnPlaceholder: false).frame(width: 46, height: 69)
            VStack(alignment: .leading, spacing: 2) {
                Text(book.shortTitle).font(.system(size: 17, weight: .semibold)).lineLimit(2)
                if !book.author.isEmpty {
                    Text(book.author).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            GetButton(book: book)
        }
        .padding(.vertical, 4)
    }
}
