import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Library tab: Continue Reading hero, then all books as a cover grid.
struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Book.addedAt, order: .reverse) private var allBooks: [Book]
    @Binding var openBook: Book?

    @State private var importing = false
    @State private var importError: String?
    @State private var actionsFor: Book?
    @State private var confirmRemove: Book?

    private var books: [Book] { allBooks.sorted { $0.recency > $1.recency } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if books.isEmpty {
                        empty
                    } else {
                        hero(books.first { $0.isStarted } ?? books[0])
                        allBooksSection
                        Text("Imported books are kept on this device.")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 40)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
                .frame(maxWidth: 1024)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { importing = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Import EPUB")
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "epub") ?? .data], allowsMultipleSelection: true) { result in
                handleImport(result)
            }
            .alert("Couldn’t Import", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(importError ?? "") }
            .confirmationDialog(actionsFor?.title ?? "", isPresented: Binding(get: { actionsFor != nil }, set: { if !$0 { actionsFor = nil } }), titleVisibility: .visible, presenting: actionsFor) { book in
                Button(book.isStarted ? "Continue Reading" : "Read") { openBook = book }
                Button("Remove from Library", role: .destructive) { confirmRemove = book }
            } message: { book in
                Text([book.author, book.isStarted ? "\(Int(book.progress * 100))% read" : "Not started"].filter { !$0.isEmpty }.joined(separator: " · "))
            }
            .alert("Remove Book?", isPresented: Binding(get: { confirmRemove != nil }, set: { if !$0 { confirmRemove = nil } }), presenting: confirmRemove) { book in
                Button("Remove", role: .destructive) { LibraryStore.remove(book, from: context) }
                Button("Cancel", role: .cancel) {}
            } message: { book in
                Text("“\(book.title)” will be removed from this device. Words you saved from it stay in Vocabulary.")
            }
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                do { try LibraryStore.importEpub(at: url, into: context) } catch {
                    importError = (error as? LocalizedError)?.errorDescription ?? "\(url.lastPathComponent) couldn’t be imported."
                }
            }
        case .failure(let error):
            importError = error.localizedDescription
        }
    }

    // MARK: Sections

    private var empty: some View {
        VStack(spacing: 8) {
            Text("Your library is empty").font(.title3.weight(.semibold))
            Text("Import an EPUB from Files to start reading.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Import EPUB") { importing = true }
                .buttonStyle(InkButtonStyle())
                .padding(.top, 14)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 64)
    }

    private func sectionHead(_ title: String, trailing: String? = nil) -> some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 22, weight: .bold))
                Spacer()
                if let trailing { Text(trailing).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary) }
            }
            Divider()
        }
        .padding(.top, 24)
        .padding(.bottom, 14)
    }

    private func hero(_ book: Book) -> some View {
        let started = book.isStarted
        let pct = Int((book.progress * 100).rounded())
        return VStack(alignment: .leading, spacing: 0) {
            sectionHead(started ? "Continue Reading" : "Start Reading")
            HStack(alignment: .bottom, spacing: 20) {
                Button { openBook = book } label: { CoverView(book: book) }
                    .buttonStyle(.plain)
                    .frame(width: 132)
                    .accessibilityLabel("Open \(book.title)")
                VStack(alignment: .leading, spacing: 4) {
                    let eyebrow = started && !book.chapterLabel.isEmpty ? book.chapterLabel : book.author
                    if !eyebrow.isEmpty {
                        Text(eyebrow).font(.footnote.weight(.medium)).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Text(book.title)
                        .font(.system(size: 22, weight: .semibold, design: .serif))
                        .fixedSize(horizontal: false, vertical: true)
                    if started {
                        if !book.author.isEmpty { Text(book.author).font(.subheadline).foregroundStyle(.secondary) }
                        HStack(spacing: 10) {
                            ProgressMeter(value: max(book.progress, 0.01)).frame(maxWidth: 160)
                            Text("\(pct)%").font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        .padding(.top, 10)
                    }
                    Button(started ? "Continue" : "Read") { openBook = book }
                        .buttonStyle(InkButtonStyle(small: true))
                        .padding(.top, 14)
                }
                .padding(.bottom, 4)
                Spacer(minLength: 0)
            }
        }
    }

    private var allBooksSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHead("All Books", trailing: "\(books.count) \(books.count == 1 ? "Book" : "Books")")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 132, maximum: 220), spacing: 24, alignment: .bottom)], spacing: 28) {
                ForEach(books) { book in
                    VStack(spacing: 8) {
                        Button { openBook = book } label: { CoverView(book: book) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Open \(book.title)")
                        HStack {
                            status(book)
                            Spacer()
                            Button { actionsFor = book } label: {
                                Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 32, height: 22)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, -6)
                            .accessibilityLabel("More actions for \(book.title)")
                        }
                        .frame(minHeight: 22)
                    }
                }
            }
        }
    }

    @ViewBuilder private func status(_ book: Book) -> some View {
        if !book.isStarted {
            Text("NEW").font(.system(size: 11, weight: .semibold)).tracking(0.66)
        } else if book.progress >= 0.995 {
            Text("Finished").font(.footnote).foregroundStyle(.secondary)
        } else {
            Text("\(max(1, Int((book.progress * 100).rounded())))%").font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
        }
    }
}

/// A book cover in a 2:3 slot, sitting on the slot's bottom edge.
/// Books without a cover image get a generated cloth-colored cover.
struct CoverView: View {
    let book: Book

    private static let cloth: [Color] = [
        Color(red: 0.23, green: 0.21, blue: 0.19), Color(red: 0.18, green: 0.24, blue: 0.27),
        Color(red: 0.29, green: 0.18, blue: 0.18), Color(red: 0.19, green: 0.25, blue: 0.20),
        Color(red: 0.25, green: 0.22, blue: 0.30), Color(red: 0.32, green: 0.26, blue: 0.18),
    ]

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 2, bottomLeadingRadius: 2, bottomTrailingRadius: 4, topTrailingRadius: 4)
    }

    var body: some View {
        Color.clear
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .overlay(alignment: .bottom) {
                if let data = book.coverData, let img = UIImage(data: data) {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(shape)
                        .modifier(CoverShadow())
                } else {
                    generated
                }
            }
    }

    private var generated: some View {
        let color = Self.cloth[abs(book.title.hashValue) % Self.cloth.count]
        return VStack(alignment: .leading) {
            Text(book.title).font(.system(size: 17, weight: .semibold, design: .serif))
            Spacer()
            Text(book.author.uppercased()).font(.system(size: 11, weight: .medium)).tracking(0.66).opacity(0.7)
        }
        .foregroundStyle(Color(red: 0.96, green: 0.94, blue: 0.90))
        .padding(.vertical, 18)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(color, in: shape)
        .modifier(CoverShadow())
    }
}

struct CoverShadow: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content
            .shadow(color: .black.opacity(scheme == .dark ? 0.6 : 0.18), radius: 0.5, y: 0.5)
            .shadow(color: .black.opacity(scheme == .dark ? 0.5 : 0.12), radius: 10, y: 8)
    }
}

/// Thin progress bar like the web `.meter`.
struct ProgressMeter: View {
    let value: Double
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.tertiarySystemFill))
                Capsule().fill(Color.primary).frame(width: g.size.width * min(1, value))
            }
        }
        .frame(height: 3)
    }
}

/// Filled pill button in "ink" (near-black in light mode, near-white in dark),
/// like the web app's `.btn`. Explicit colours: inside iOS 26 sheets, semantic
/// `.primary` fills are drawn with vibrancy and look grey.
struct InkButtonStyle: ButtonStyle {
    var small = false
    var block = false

    func makeBody(configuration: Configuration) -> some View {
        InkLabel(configuration: configuration, small: small, block: block)
    }

    private struct InkLabel: View {
        let configuration: Configuration
        let small: Bool
        let block: Bool
        @Environment(\.colorScheme) private var scheme
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            let ink = scheme == .dark ? Color(red: 0.949, green: 0.949, blue: 0.969) : Color(red: 0.110, green: 0.110, blue: 0.118)
            let onInk = scheme == .dark ? Color.black : Color.white
            configuration.label
                .font(.system(size: small ? 15 : 17, weight: .semibold))
                .foregroundStyle(onInk)
                .padding(.horizontal, small ? 16 : 24)
                .frame(maxWidth: block ? .infinity : nil)
                .frame(height: small ? 36 : 50)
                .background(ink, in: Capsule())
                .opacity(configuration.isPressed ? 0.7 : enabled ? 1 : 0.35)
        }
    }
}
