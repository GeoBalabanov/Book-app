import SwiftData
import SwiftUI

/// Vocabulary tab: saved words with search, a book filter and swipe to delete.
/// Ported from web/js/views/vocabulary.js.
struct VocabularyView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SavedWord.addedAt, order: .reverse) private var words: [SavedWord]

    @State private var query = ""
    @State private var book = ""          // "" = all books
    @State private var selected: SavedWord?

    private var books: [String] {
        Array(Set(words.map(\.bookTitle).filter { !$0.isEmpty })).sorted()
    }

    private var filtered: [SavedWord] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return words.filter { w in
            (book.isEmpty || w.bookTitle == book)
                && (q.isEmpty || [w.word, w.lemma, w.translation, w.dictionaryTranslation].contains { $0.lowercased().contains(q) })
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if words.isEmpty {
                    ContentUnavailableView {
                        Label("No Saved Words", systemImage: "character.book.closed")
                    } description: {
                        Text("While reading, touch and hold a word to look it up, then tap Save to Flashcards.")
                    }
                } else {
                    list
                }
            }
            .navigationTitle("Vocabulary")
        }
        .sheet(item: $selected) { word in
            LookUpSheet(request: word.asRequest, savedEntry: word)
        }
        .onChange(of: books) { if !book.isEmpty && !books.contains(book) { book = "" } }
    }

    private var list: some View {
        List {
            Section {
                if filtered.isEmpty {
                    Text("No results for “\(query)”")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(filtered) { word in
                        Button { selected = word } label: { VocabularyRow(word: word) }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button("Delete", role: .destructive) { delete(word) }
                            }
                    }
                }
            } header: {
                HStack {
                    Text(caption).monospacedDigit()
                    Spacer()
                    if books.count >= 2 { bookMenu }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search")
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
    }

    private var caption: String {
        let n = filtered.count, total = words.count
        return n == total ? "\(n) \(n == 1 ? "Word" : "Words")" : "\(n) of \(total) Words"
    }

    private var bookMenu: some View {
        Menu {
            Picker("Book", selection: $book) {
                Text("All Books").tag("")
                ForEach(books, id: \.self) { Text($0).tag($0) }
            }
        } label: {
            HStack(spacing: 3) {
                Text(book.isEmpty ? "All Books" : book).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.caption2)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.primary)
            .textCase(nil)
        }
        .accessibilityLabel("Filter by book")
    }

    private func delete(_ word: SavedWord) {
        withAnimation {
            context.delete(word)
            try? context.save()
        }
    }
}

struct VocabularyRow: View {
    let word: SavedWord

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(word.word).font(.body.weight(.semibold))
                Spacer(minLength: 0)
                Text(word.translation)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Text(LookUpSheet.boldSentence(word.sentence, word: word.word, offset: word.offset))
                .font(.system(size: 14, design: .serif))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows the saved word")
    }
}
