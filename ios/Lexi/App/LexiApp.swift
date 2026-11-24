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
            container = try ModelContainer(for: Book.self, CachedTranslation.self, SavedWord.self, ReadingDay.self)
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
    @State private var router = AppRouter()
    @Query private var savedWords: [SavedWord]

    /// Cards due today, shown as a badge on the Flashcards tab.
    private var dueCount: Int { savedWords.filter { SM2.isDueToday($0.due) }.count }

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(AppRouter.Tab.home)
            LibraryView(openBook: $router.openBook)
                .tabItem { Label("Library", systemImage: "books.vertical") }
                .tag(AppRouter.Tab.library)
            VocabularyView()
                .tabItem { Label("Vocabulary", systemImage: "character.book.closed") }
                .tag(AppRouter.Tab.vocabulary)
            FlashcardsView()
                .tabItem { Label("Flashcards", systemImage: "rectangle.on.rectangle.angled") }
                .badge(dueCount)
                .tag(AppRouter.Tab.flashcards)
            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(AppRouter.Tab.search)
        }
        .environment(router)
        .onAppear { LibraryStore.ensureSample(in: context) }
        // The reader overrides its own presentation's color scheme to match the page,
        // so the device appearance is read here, outside it, for the "Auto" setting.
        .fullScreenCover(item: $router.openBook) { book in
            ReaderView(book: book, systemScheme: colorScheme) { router.openBook = nil }
        }
    }
}
