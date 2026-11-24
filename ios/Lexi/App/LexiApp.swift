import CoreText
import SwiftData
import SwiftUI

@main
struct LexiApp: App {
    let container: ModelContainer

    init() {
        // Bundled Literata (also used by the reader page) so native previews can show it.
        for url in Bundle.main.urls(forResourcesWithExtension: "woff2", subdirectory: nil) ?? [] {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        do {
            container = try ModelContainer(for: Book.self, CachedTranslation.self)
        } catch {
            fatalError("Could not open the Lexi data store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(.primary)
        }
        .modelContainer(container)
    }
}

/// Tabs: Library · Vocabulary · Flashcards. The reader is presented full screen over them.
struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var colorScheme
    @State private var openBook: Book?

    var body: some View {
        TabView {
            LibraryView(openBook: $openBook)
                .tabItem { Label("Library", systemImage: "books.vertical") }
            PlaceholderTab(title: "Vocabulary", message: "Words you save while reading will appear here.")
                .tabItem { Label("Vocabulary", systemImage: "character.book.closed") }
            PlaceholderTab(title: "Flashcards", message: "Review saved words with spaced repetition.")
                .tabItem { Label("Flashcards", systemImage: "rectangle.on.rectangle.angled") }
        }
        .onAppear { LibraryStore.ensureSample(in: context) }
        // The reader overrides its own presentation's color scheme to match the page,
        // so the device appearance is read here, outside it, for the "Auto" setting.
        .fullScreenCover(item: $openBook) { book in
            ReaderView(book: book, systemScheme: colorScheme) { openBook = nil }
        }
    }
}

struct PlaceholderTab: View {
    let title: String
    let message: String
    var body: some View {
        NavigationStack {
            ContentUnavailableView(title, systemImage: "hourglass", description: Text(message))
                .navigationTitle(title)
        }
    }
}
