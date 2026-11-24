import SwiftData
import SwiftUI

/// Look Up sheet, styled like Apple's dictionary sheet: the word, grammar,
/// its Bulgarian meaning in this sentence, the sentence with the word in bold,
/// and the sentence in Bulgarian.
struct LookUpSheet: View {
    let request: LookupRequest
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var result: LookupResult?
    @State private var error: String?
    @State private var loading = true

    private let service = TranslationProviders.current

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Look Up") { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    head
                    sentenceSection
                    footer
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
        .task(id: request.id) { await run() }
    }

    private func run() async {
        loading = true
        error = nil
        do {
            result = try await Translator.lookup(request, in: context, service: service)
        } catch is CancellationError {
            return
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "Translation failed."
        }
        loading = false
    }

    // MARK: Sections

    private var head: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(request.word)
                .font(.system(size: 32, weight: .bold, design: .serif))
                .textSelection(.enabled)
            if let gram = grammarLine {
                gram
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            }
            if loading {
                SkeletonBar(width: 0.5, height: 28).padding(.top, 14)
            } else if let error {
                VStack(alignment: .leading, spacing: 10) {
                    Text(error).font(.subheadline).foregroundStyle(.red)
                    Button("Try Again") { Task { await run() } }
                        .buttonStyle(InkButtonStyle(small: true))
                }
                .padding(.top, 14)
            } else if let r = result {
                Text(r.translation)
                    .font(.system(size: 26, design: .serif))
                    .textSelection(.enabled)
                    .padding(.top, 14)
                if !r.dictionaryTranslation.isEmpty, r.dictionaryTranslation != r.translation {
                    Text("\(r.lemma): \(r.dictionaryTranslation)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                }
            }
        }
        .padding(.top, 2)
        .padding(.bottom, 16)
    }

    /// "verb · base form be"
    private var grammarLine: Text? {
        guard let r = result else { return nil }
        var parts: [Text] = []
        if !r.partOfSpeech.isEmpty { parts.append(Text(r.partOfSpeech).font(.system(.subheadline, design: .serif)).italic()) }
        if !r.lemma.isEmpty, r.lemma.lowercased() != request.word.lowercased() { parts.append(Text("base form \(r.lemma)")) }
        guard var line = parts.first else { return nil }
        for p in parts.dropFirst() { line = line + Text(" · ") + p }
        return line
    }

    private var sentenceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(request.bookTitle.isEmpty ? "IN THE BOOK" : request.bookTitle.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            Text(Self.boldSentence(request.sentence, word: request.word, offset: request.offset))
                .font(.system(size: 17, design: .serif))
                .lineSpacing(5)
                .textSelection(.enabled)
            if loading {
                SkeletonBar(width: 1, height: 15)
                SkeletonBar(width: 0.65, height: 15)
            } else if let r = result, !r.sentenceTranslation.isEmpty {
                Text(r.sentenceTranslation)
                    .font(.system(size: 17, design: .serif))
                    .lineSpacing(5)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Divider() }
    }

    @ViewBuilder private var footer: some View {
        if result != nil {
            Text(service.attribution)
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .padding(.top, 6)
        }
    }

    /// The sentence with the looked-up word in bold (offset is in UTF-16 units).
    static func boldSentence(_ sentence: String, word: String, offset: Int) -> AttributedString {
        var out = AttributedString(sentence)
        let ns = sentence as NSString
        var r = NSRange(location: offset, length: (word as NSString).length)
        if offset < 0 || r.upperBound > ns.length || ns.substring(with: r) != word { r = ns.range(of: word) }
        if r.location != NSNotFound, let range = Range(r, in: sentence),
           let lower = AttributedString.Index(range.lowerBound, within: out),
           let upper = AttributedString.Index(range.upperBound, within: out) {
            out[lower..<upper].inlinePresentationIntent = .stronglyEmphasized
            out[lower..<upper].foregroundColor = .primary
        }
        return out
    }
}

/// Shimmering placeholder line.
struct SkeletonBar: View {
    var width: CGFloat
    var height: CGFloat
    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { g in
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(.quaternarySystemFill))
                .overlay {
                    LinearGradient(colors: [.clear, Color(.tertiarySystemFill), .clear], startPoint: .leading, endPoint: .trailing)
                        .offset(x: phase * g.size.width * width)
                }
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .frame(width: g.size.width * width)
        }
        .frame(height: height)
        .onAppear {
            withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1 }
        }
    }
}
