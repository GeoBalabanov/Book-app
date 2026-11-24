import SwiftData
import SwiftUI

/// Home tab: Top Picks (from the Gutenberg catalogue), Previous (books you've
/// opened) and Reading Goals (daily reading time and streak).
struct HomeView: View {
    @Environment(AppRouter.self) private var router
    @Query(sort: \Book.addedAt) private var library: [Book]
    @State private var catalog = GutenbergCatalog.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 40) {
                    topPicks
                    if !previous.isEmpty { previousSection }
                    ReadingGoalsSection(keepReading: previous.first)
                }
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .navigationTitle("Home")
            .navigationDestination(for: Shelf.self) { ShelfView(shelf: $0) }
            .navigationDestination(for: CatalogBook.self) { BookDetailView(book: $0) }
        }
        .task { await catalog.load() }
    }

    private var previous: [Book] {
        library.filter(\.isStarted).sorted { $0.recency > $1.recency }
    }

    private var shelves: [Shelf] {
        guard catalog.isLoaded else { return [] }
        let owned = Set(library.compactMap(\.gutenbergID))
        return [Shelves.suggestions(library: library, catalog: catalog)]
            + Shelves.genres.prefix(6).map { Shelves.genre($0, catalog: catalog, owned: owned) }
    }

    // MARK: Top Picks

    private var topPicks: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle("Top Picks")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    if shelves.isEmpty {
                        ShelfCardPlaceholder()
                    }
                    ForEach(shelves) { shelf in
                        NavigationLink(value: shelf) { ShelfCard(shelf: shelf) }
                            .buttonStyle(.plain)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .contentMargins(.horizontal, 20, for: .scrollContent)
        }
    }

    // MARK: Previous

    private var previousSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button { router.tab = .library } label: {
                HStack(spacing: 6) {
                    SectionTitle("Previous")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows your Library")

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(previous) { book in
                        PreviousCard(book: book)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .contentMargins(.horizontal, 20, for: .scrollContent)
        }
    }
}

/// Large serif section title, like Apple Books' Home.
struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 28, weight: .bold, design: .serif))
            .padding(.horizontal, 20)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Top Picks card

/// One Top Picks card: a large cover and a 2×2 grid of smaller ones, then the
/// shelf title and subtitle.
struct ShelfCard: View {
    let shelf: Shelf

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: 12) {
                if let first = shelf.books.first {
                    RemoteCover(book: first).frame(width: 150, height: 225)
                }
                Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                    GridRow { small(1); small(3) }
                    GridRow { small(2); small(4) }
                }
            }
            .frame(width: 290, height: 230, alignment: .bottomLeading)
            .clipped()
            .padding(.top, 22)
            .padding(.leading, 22)

            VStack(alignment: .leading, spacing: 4) {
                Text(shelf.title)
                    .font(.system(size: 21, weight: .semibold))
                    .lineLimit(1)
                Text(shelf.subtitle)
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 22)
        }
        .frame(width: 312, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(shelf.title). \(shelf.subtitle)")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder private func small(_ i: Int) -> some View {
        if i < shelf.books.count {
            RemoteCover(book: shelf.books[i], showsTitleOnPlaceholder: false).frame(width: 72, height: 108)
        } else {
            Color.clear.frame(width: 72, height: 108)
        }
    }
}

struct ShelfCardPlaceholder: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Color(.secondarySystemBackground))
            .frame(width: 312, height: 380)
            .overlay { ProgressView() }
    }
}

// MARK: - Previous card

/// A book you've opened: cover, title, author and progress, with a ⋯ menu.
struct PreviousCard: View {
    let book: Book
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @State private var confirmRemove = false

    var body: some View {
        HStack(spacing: 16) {
            CoverView(book: book).frame(width: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(book.title).font(.system(size: 17, weight: .semibold)).lineLimit(2)
                if !book.author.isEmpty {
                    Text(book.author).font(.system(size: 16)).foregroundStyle(.secondary).lineLimit(1)
                }
                status.font(.system(size: 15)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Menu {
                Button("Read", systemImage: "book") { router.openBook = book }
                Button("Remove from Library", systemImage: "trash", role: .destructive) { confirmRemove = true }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("More actions for \(book.title)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: 320, height: 112)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture { router.openBook = book }
        .accessibilityAddTraits(.isButton)
        .alert("Remove Book?", isPresented: $confirmRemove) {
            Button("Remove", role: .destructive) { LibraryStore.remove(book, from: context) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("“\(book.title)” will be removed from this device. Words you saved from it stay in Vocabulary.")
        }
    }

    @ViewBuilder private var status: some View {
        if book.progress >= 0.995 {
            Label("Finished", systemImage: "checkmark.circle.fill")
        } else {
            Text("Book · \(max(1, Int((book.progress * 100).rounded())))%")
        }
    }
}

// MARK: - Reading Goals

/// Today's reading time against the daily goal, Keep Reading, this week's
/// goal days and the current streak.
struct ReadingGoalsSection: View {
    let keepReading: Book?

    @Environment(AppRouter.self) private var router
    @Query private var days: [ReadingDay]
    @State private var goal = ReadingStats.goalMinutes
    @State private var editingGoal = false
    @State private var now = Date.now

    private var seconds: [String: Double] { Dictionary(days.map { ($0.day, $0.seconds) }, uniquingKeysWith: +) }
    private var today: Double { seconds[ReadingStats.key(for: now)] ?? 0 }
    private var progress: Double { min(1, today / Double(goal * 60)) }

    var body: some View {
        VStack(spacing: 0) {
            Text("Reading Goals")
                .font(.system(size: 28, weight: .bold, design: .serif))
                .accessibilityAddTraits(.isHeader)
            Text("Read every day, see your stats soar and finish more books.")
                .font(.system(size: 17))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 6)

            ZStack {
                GoalArc(progress: progress)
                    .frame(width: 300, height: 300)
                    .offset(y: 40)
                VStack(spacing: 2) {
                    Text("Today’s Reading")
                        .font(.system(size: 22, weight: .semibold, design: .serif))
                    Text(ReadingStats.format(today))
                        .font(.system(size: 76, weight: .regular, design: .serif).monospacedDigit())
                        .contentTransition(.numericText())
                    Button { editingGoal = true } label: {
                        HStack(spacing: 4) {
                            Text("of your \(goal)-minute goal")
                            Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(.secondary)
                        }
                        .font(.system(size: 18))
                    }
                    .buttonStyle(.plain)
                }
                .offset(y: 30)
            }
            .frame(height: 260)
            .padding(.top, 28)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Today’s reading: \(Int(today / 60)) of \(goal) minutes")

            if let book = keepReading {
                Button { router.openBook = book } label: {
                    VStack(spacing: 2) {
                        Text("Keep Reading").font(.system(size: 18, weight: .semibold))
                        Text(book.title).font(.system(size: 15)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(Color(.tertiarySystemFill), in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 32)
            }

            WeekDots(seconds: seconds, goal: goal, now: now)
                .padding(.top, 32)

            let streak = ReadingStats.currentStreak(seconds: seconds, goal: goal, now: now)
            VStack(spacing: 2) {
                Text(streak > 0 ? "\(streak)-day streak" : "Start a new streak.")
                    .font(.system(size: 17))
                Text(streak > 0 ? "Keep it going: read today to make it \(streak + (progress >= 1 ? 0 : 1))." : "Read daily and set new records.")
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 18)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
        .onAppear { now = .now; goal = ReadingStats.goalMinutes }
        .sheet(isPresented: $editingGoal) {
            GoalSheet(goal: $goal)
        }
    }
}

/// 240° arc open at the bottom, filled clockwise with today's progress.
struct GoalArc: View {
    let progress: Double
    private let sweep = 240.0 / 360.0

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: sweep)
                .stroke(Color(.tertiarySystemFill), style: StrokeStyle(lineWidth: 14, lineCap: .round))
            Circle()
                .trim(from: 0, to: sweep * progress)
                .stroke(Color.primary, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .animation(.easeOut(duration: 0.6), value: progress)
        }
        .rotationEffect(.degrees(150))
        .accessibilityHidden(true)
    }
}

/// This week, Monday or Sunday first per locale: filled when the goal was met.
struct WeekDots: View {
    let seconds: [String: Double]
    let goal: Int
    let now: Date

    var body: some View {
        let cal = Calendar.current
        let start = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? cal.startOfDay(for: now)
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { i in
                let day = cal.date(byAdding: .day, value: i, to: start)!
                let met = (seconds[ReadingStats.key(for: day)] ?? 0) >= Double(goal * 60)
                let isToday = cal.isDate(day, inSameDayAs: now)
                let future = day > now && !isToday
                Text(symbols[cal.component(.weekday, from: day) - 1])
                    .font(.system(size: 17, weight: isToday ? .semibold : .regular))
                    .foregroundStyle(met ? Color(.systemBackground) : (future ? Color.secondary : Color.primary))
                    .frame(width: 40, height: 40)
                    .background {
                        if met { Circle().fill(Color.primary) }
                        else if isToday { Circle().fill(Color(.tertiarySystemFill)) }
                    }
                    .overlay {
                        if !met { Circle().strokeBorder(Color(.separator), lineWidth: isToday ? 0 : 2) }
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("\(day.formatted(.dateTime.weekday(.wide)))\(met ? ", goal met" : "")")
            }
        }
    }
}

/// Picker for the daily reading goal.
struct GoalSheet: View {
    @Binding var goal: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(ReadingStats.goalOptions, id: \.self) { minutes in
                        Button {
                            goal = minutes
                            ReadingStats.goalMinutes = minutes
                            dismiss()
                        } label: {
                            HStack {
                                Text(minutes == 1 ? "1 minute a day" : "\(minutes) minutes a day")
                                Spacer()
                                if minutes == goal { Image(systemName: "checkmark").fontWeight(.semibold) }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } footer: {
                    Text("Time counts while you turn pages, look up words and tap in a book. A pause of more than two minutes doesn’t count.")
                }
            }
            .navigationTitle("Daily Reading Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
