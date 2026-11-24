import SwiftData
import SwiftUI

/// Flashcards tab: a deck screen (fanned stack, counts, 7-day forecast), a
/// study session with paper index cards, and a session summary.
/// Ported from web/js/views/flashcards.js.
struct FlashcardsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SavedWord.addedAt) private var words: [SavedWord]   // oldest first = card numbers

    @State private var session: StudySession?
    @State private var summary: StudySession?
    /// Re-evaluated when the tab appears so "due today" stays current.
    @State private var now = Date.now

    var body: some View {
        NavigationStack {
            Group {
                if let session {
                    StudyView(session: session, number: number(for:)) { finished in
                        withAnimation(.easeInOut(duration: 0.25)) {
                            self.session = nil
                            if finished.done > 0 { summary = finished }
                            now = .now
                        }
                    }
                } else if let summary {
                    SummaryView(session: summary) {
                        withAnimation { self.summary = nil; now = .now }
                    }
                } else if words.isEmpty {
                    ContentUnavailableView {
                        Label("No Cards Yet", systemImage: "rectangle.on.rectangle.angled")
                    } description: {
                        Text("Words you save while reading become cards here, each shown in the sentence where you found it.")
                    }
                } else {
                    ScrollView { deck.padding(.horizontal, 20).padding(.bottom, 32) }
                }
            }
            .navigationTitle(session == nil ? "Flashcards" : "")
            .navigationBarTitleDisplayMode(session == nil ? .large : .inline)
            .toolbar(session == nil ? .visible : .hidden, for: .tabBar)
        }
        .onAppear { now = .now }
    }

    /// Card number = order in which the word was saved (an index-card detail).
    private func number(for word: SavedWord) -> Int {
        (words.firstIndex { $0.id == word.id } ?? 0) + 1
    }

    // MARK: Deck

    private var due: [SavedWord] {
        words.filter { SM2.isDueToday($0.due, now: now) }.sorted { $0.due < $1.due }
    }

    private var deck: some View {
        let due = due
        let fresh = due.filter(\.isNew).count
        let learned = words.filter { $0.repetitions >= 2 }.count
        let next = words.filter { !SM2.isDueToday($0.due, now: now) }.min { $0.due < $1.due }
        let top = due.first ?? next ?? words[0]

        return VStack(spacing: 0) {
            Fan(word: top, label: due.isEmpty ? "Next" : "Up next", number: number(for: top))
                .padding(.top, 18)
                .padding(.bottom, 40)

            Text(due.isEmpty ? "You’re all caught up" : "\(due.count) \(due.count == 1 ? "card" : "cards") due today")
                .font(.system(size: 22, weight: .semibold))

            HStack(spacing: 0) {
                figure(fresh, "New")
                Divider().frame(height: 34)
                figure(due.count - fresh, "Review")
                Divider().frame(height: 34)
                figure(learned, "Learned")
            }
            .fixedSize()
            .padding(.top, 18)

            if !due.isEmpty {
                Button("Review Now") { start(due) }
                    .buttonStyle(InkButtonStyle())
                    .frame(minWidth: 220)
                    .padding(.top, 28)
            } else if let next {
                Text("Next review in \(SM2.formatRelative(next.due.timeIntervalSince(now)))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)
            }

            WeekForecast(dues: words.map(\.due), now: now)
                .frame(maxWidth: 320)
                .padding(.top, 36)
        }
        .frame(maxWidth: .infinity)
    }

    private func figure(_ value: Int, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)").font(.system(size: 26, weight: .medium, design: .serif).monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 22)
        .accessibilityElement(children: .combine)
    }

    private func start(_ due: [SavedWord]) {
        withAnimation(.easeInOut(duration: 0.25)) {
            summary = nil
            session = StudySession(queue: due.map(\.id))
        }
    }
}

// MARK: - Session model

@Observable
final class StudySession {
    var queue: [String]
    var done = 0
    var tally: [SM2.Grade: Int] = [:]
    let started = Date.now

    init(queue: [String]) { self.queue = queue }
}

// MARK: - Deck pieces

/// Three index cards fanned out, the top one showing the next word.
private struct Fan: View {
    let word: SavedWord
    let label: String
    let number: Int
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            IndexCardBackground()
                .rotationEffect(.degrees(-6)).offset(x: -14, y: 8).opacity(0.9)
            IndexCardBackground()
                .rotationEffect(.degrees(3.5)).offset(x: 12, y: 2)
            VStack(spacing: 0) {
                IndexCardHeader(label: label, number: number)
                Spacer(minLength: 0)
                Text(word.word)
                    .font(.system(size: 34, weight: .medium, design: .serif))
                    .foregroundStyle(Paper.ink(scheme))
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 18)
                Spacer(minLength: 0)
                Citation(title: word.bookTitle).padding(.horizontal, 20).padding(.bottom, 16)
            }
            .background(IndexCardBackground())
            .rotationEffect(.degrees(-1))
        }
        .frame(width: 300, height: 210)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(word.word)")
    }
}

/// Seven bars: cards due today (including overdue), then each of the next six days.
private struct WeekForecast: View {
    let dues: [Date]
    let now: Date

    private var counts: [Int] {
        let today = SM2.startOfDay(now)
        let cal = Calendar.current
        return (0..<7).map { i in
            dues.filter { d in
                let day = SM2.startOfDay(d)
                return i == 0 ? day <= today : day == cal.date(byAdding: .day, value: i, to: today)
            }.count
        }
    }

    var body: some View {
        let counts = counts
        let maxCount = max(1, counts.max() ?? 1)
        let today = SM2.startOfDay(now)
        VStack(alignment: .leading, spacing: 8) {
            Text("COMING UP").font(.caption).tracking(0.5).foregroundStyle(.secondary)
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(0..<7, id: \.self) { i in
                    let date = Calendar.current.date(byAdding: .day, value: i, to: today)!
                    VStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(i == 0 ? Color.primary : Color(.tertiarySystemFill))
                            .frame(maxWidth: 22)
                            .frame(height: CGFloat(counts[i]) / CGFloat(maxCount) * 44 + 3)
                        Text(date.formatted(.dateTime.weekday(.narrow)))
                            .font(.system(size: 11, weight: i == 0 ? .semibold : .regular).monospacedDigit())
                            .foregroundStyle(i == 0 ? .primary : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 64, alignment: .bottom)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cards due over the next 7 days: \(counts.map(String.init).joined(separator: ", "))")
    }
}

// MARK: - Study

private struct StudyView: View {
    @Bindable var session: StudySession
    let number: (SavedWord) -> Int
    let onEnd: (StudySession) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    @Query private var words: [SavedWord]

    @State private var flipped = false
    @State private var showBack = false
    @State private var angle = 0.0

    private var current: SavedWord? {
        guard let id = session.queue.first else { return nil }
        return words.first { $0.id == id }
    }

    var body: some View {
        VStack(spacing: 16) {
            topBar
            if let word = current {
                card(word)
                    .id("\(word.id)-\(session.done)")
                    .transition(.asymmetric(
                        insertion: .offset(x: 28).combined(with: .opacity),
                        removal: .opacity))
                if flipped {
                    Text("How well did you know it?")
                        .font(.caption).foregroundStyle(.tertiary)
                        .transition(.opacity)
                    grades(word)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
        .onAppear(perform: skipMissing)
        .onChange(of: session.queue) { skipMissing() }
    }

    /// Words deleted mid-session drop out of the queue.
    private func skipMissing() {
        while let id = session.queue.first, !words.contains(where: { $0.id == id }) { session.queue.removeFirst() }
        if session.queue.isEmpty { onEnd(session) }
    }

    private var topBar: some View {
        let remaining = session.queue.count
        let total = session.done + remaining
        return VStack(spacing: 10) {
            ZStack {
                Text("\(min(session.done + 1, max(total, 1))) of \(total)")
                    .font(.footnote.monospacedDigit())
                    .tracking(0.3)
                    .foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("Done") { onEnd(session) }
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                }
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.tertiarySystemFill))
                    Capsule().fill(Color.primary)
                        .frame(width: g.size.width * CGFloat(session.done) / CGFloat(max(1, total)))
                        .animation(.easeOut(duration: 0.3), value: session.done)
                }
            }
            .frame(height: 2)
        }
    }

    // MARK: Card

    private func card(_ word: SavedWord) -> some View {
        let ex = CardText.excerpt(sentence: word.sentence, word: word.word, offset: word.offset)
        let ink = Paper.ink(scheme)
        let muted = Paper.muted(scheme)
        return VStack(spacing: 0) {
            if showBack {
                IndexCardHeader(label: word.word, number: number(word))
                VStack(spacing: 16) {
                    Text(word.translation)
                        .font(.system(size: 34, weight: .medium, design: .serif))
                        .foregroundStyle(ink)
                        .multilineTextAlignment(.center)
                    if let gram = grammar(word) {
                        Text(gram).font(.system(size: 15, design: .serif).italic()).foregroundStyle(muted).padding(.top, -8)
                    }
                    ornament(muted)
                    Text(CardText.quoted(ex.text, word: word.word, offset: ex.offset, ink: ink))
                        .font(.system(size: 18, design: .serif)).lineSpacing(6)
                        .foregroundStyle(ink)
                        .lineLimit(5)
                        .minimumScaleFactor(0.8)
                    if !word.sentenceTranslation.isEmpty {
                        Text(word.sentenceTranslation)
                            .font(.system(size: 16, design: .serif).italic()).lineSpacing(4)
                            .foregroundStyle(muted)
                            .lineLimit(3)
                    }
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 16)
                .frame(maxHeight: .infinity)
                HStack { Citation(title: word.bookTitle); Spacer() }
                    .padding(.horizontal, 20).padding(.bottom, 16)
            } else {
                IndexCardHeader(label: word.isNew ? "New word" : "Review", number: number(word))
                VStack(spacing: 16) {
                    Text(word.word)
                        .font(.system(size: 42, weight: .medium, design: .serif))
                        .foregroundStyle(ink)
                        .minimumScaleFactor(0.6)
                        .lineLimit(2)
                    ornament(muted)
                    Text(CardText.quoted(ex.text, word: word.word, offset: ex.offset, ink: ink))
                        .font(.system(size: 18, design: .serif)).lineSpacing(6)
                        .foregroundStyle(ink)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 16)
                .frame(maxHeight: .infinity)
                HStack(alignment: .firstTextBaseline) {
                    Citation(title: word.bookTitle)
                    Spacer(minLength: 12)
                    Text("TAP TO TURN").font(.system(size: 11, weight: .medium)).tracking(1.5).foregroundStyle(muted)
                }
                .padding(.horizontal, 20).padding(.bottom, 16)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 340, maxHeight: 440)
        .background(IndexCardBackground())
        .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
        .contentShape(Rectangle())
        .onTapGesture { flip() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(flipped ? [] : .isButton)
        .accessibilityHint(flipped ? "" : "Shows the answer")
    }

    private func ornament(_ color: Color) -> some View {
        Text("· · ·").font(.footnote).tracking(7.8).foregroundStyle(color).opacity(0.7).accessibilityHidden(true)
    }

    private func grammar(_ w: SavedWord) -> String? {
        let parts = [w.partOfSpeech, (!w.lemma.isEmpty && w.lemma.lowercased() != w.word.lowercased()) ? "from \(w.lemma)" : ""]
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// Turn the card: rotate to edge-on, swap faces, rotate back.
    private func flip() {
        guard !flipped else { return }
        flipped = true
        withAnimation(.easeIn(duration: 0.2)) { angle = 90 } completion: {
            showBack = true
            angle = -90
            withAnimation(.easeOut(duration: 0.22)) { angle = 0 }
        }
    }

    // MARK: Grades

    private func grades(_ word: SavedWord) -> some View {
        let preview = SM2.previewIntervals(word.reviewState)
        return HStack(spacing: 0) {
            ForEach(SM2.Grade.allCases) { g in
                if g != .again { Rectangle().fill(.separator).frame(width: 0.5).padding(.vertical, 12) }
                Button { grade(word, g) } label: {
                    VStack(spacing: 3) {
                        Text(g.label).font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(g == .again ? Color.red : Color.primary)
                        Text(SM2.formatRelative(preview[g] ?? 0))
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 11).padding(.bottom, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(g.label), next review in \(SM2.formatRelative(preview[g] ?? 0))")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(.quaternarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func grade(_ word: SavedWord, _ g: SM2.Grade) {
        word.reviewState = SM2.review(word.reviewState, g)
        try? context.save()
        UIImpactFeedbackGenerator(style: g == .again ? .rigid : .light).impactOccurred()
        withAnimation(.spring(duration: 0.35, bounce: 0.15)) {
            session.queue.removeFirst()
            session.done += 1
            session.tally[g, default: 0] += 1
            if g == .again { session.queue.append(word.id) }   // comes back this session
            flipped = false
            showBack = false
            angle = 0
        }
        if session.queue.isEmpty { onEnd(session) }
    }
}

// MARK: - Summary

private struct SummaryView: View {
    let session: StudySession
    let onDone: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                VStack(spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("TODAY’S SESSION").font(.system(size: 11, weight: .semibold)).tracking(1.5)
                        Spacer()
                        Text(session.started.formatted(.dateTime.day().month(.abbreviated)))
                            .font(.system(size: 13, design: .serif).italic())
                    }
                    .foregroundStyle(Paper.muted(scheme))
                    .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 9)
                    .overlay(alignment: .bottom) { Rectangle().fill(Paper.rule(scheme)).frame(height: 1) }

                    VStack(spacing: 0) {
                        ForEach(Array(SM2.Grade.allCases.enumerated()), id: \.element) { i, g in
                            HStack {
                                Text(g.label)
                                Spacer()
                                Text("\(session.tally[g] ?? 0)").fontWeight(.medium).monospacedDigit()
                            }
                            .font(.system(size: 17, design: .serif))
                            .foregroundStyle(Paper.ink(scheme))
                            .padding(.vertical, 9)
                            .overlay(alignment: .bottom) {
                                if i < 3 { Rectangle().fill(Paper.rule(scheme)).frame(height: 1) }
                            }
                        }
                    }
                    .padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 14)
                }
                .frame(width: 320)
                .background(IndexCardBackground())
                .rotationEffect(.degrees(-1))
                .padding(.bottom, 26)
                .accessibilityElement(children: .combine)

                Text("Session Complete").font(.system(size: 22, weight: .semibold))
                Text("You reviewed \(session.done) \(session.done == 1 ? "card" : "cards"). The ones you found hard will come back sooner.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
                Button("Done", action: onDone)
                    .buttonStyle(InkButtonStyle())
                    .frame(minWidth: 200)
                    .padding(.top, 22)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
            .padding(.horizontal, 20)
        }
    }
}
