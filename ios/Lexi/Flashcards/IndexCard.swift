import SwiftUI

/// Paper index-card styling, from the web app's `.index-card` rules:
/// warm paper with faint grain, a ruled header, serif text.
enum Paper {
    static func stock(_ s: ColorScheme) -> Color { s == .dark ? Color(red: 0x22/255, green: 0x20/255, blue: 0x1c/255) : Color(red: 0xfb/255, green: 0xf8/255, blue: 0xf1/255) }
    static func ink(_ s: ColorScheme) -> Color { s == .dark ? Color(red: 0xed/255, green: 0xe6/255, blue: 0xd8/255) : Color(red: 0x22/255, green: 0x1d/255, blue: 0x17/255) }
    static func muted(_ s: ColorScheme) -> Color { s == .dark ? Color(red: 0x9a/255, green: 0x90/255, blue: 0x7f/255) : Color(red: 0x8b/255, green: 0x81/255, blue: 0x74/255) }
    static func rule(_ s: ColorScheme) -> Color { s == .dark ? Color(red: 237/255, green: 230/255, blue: 216/255).opacity(0.1) : Color(red: 120/255, green: 90/255, blue: 60/255).opacity(0.18) }
    /// Warm marker under the word in quoted sentences.
    static let marker = Color(red: 214/255, green: 170/255, blue: 90/255).opacity(0.28)
}

/// The card itself: stock, grain, rounded corners and a soft shadow.
struct IndexCardBackground: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Paper.stock(scheme))
            .overlay { CardGrain(dark: scheme == .dark).clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous)) }
            .overlay {
                if scheme == .dark { RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.white.opacity(0.06), lineWidth: 0.5) }
            }
            .shadow(color: Color(red: 60/255, green: 40/255, blue: 20/255).opacity(scheme == .dark ? 0 : 0.06), radius: 1, y: 1)
            .shadow(color: Color(red: 60/255, green: 40/255, blue: 20/255).opacity(scheme == .dark ? 0 : 0.08), radius: 7, y: 6)
            .shadow(color: (scheme == .dark ? Color.black : Color(red: 60/255, green: 40/255, blue: 20/255)).opacity(scheme == .dark ? 0.7 : 0.22), radius: 20, y: 18)
    }
}

/// Fine paper grain (deterministic noise).
struct CardGrain: View {
    let dark: Bool
    var body: some View {
        Canvas { ctx, size in
            var rng = SeededRandom(seed: 11)
            let color = dark ? Color.white.opacity(0.035) : Color(red: 0.45, green: 0.38, blue: 0.3).opacity(0.07)
            for _ in 0..<Int(size.width * size.height / 9) {
                let x = Double(rng.next() % 10_000) / 10_000 * size.width
                let y = Double(rng.next() % 10_000) / 10_000 * size.height
                ctx.fill(Path(CGRect(x: x, y: y, width: 1, height: 1)), with: .color(color))
            }
        }
        .allowsHitTesting(false)
    }
}

/// Ruled header: small caps label on the left, an italic "No. 12" on the right.
struct IndexCardHeader: View {
    let label: String
    let number: Int
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.5)
                .lineLimit(1)
            Spacer(minLength: 12)
            Text("No. \(number)")
                .font(.system(size: 13, design: .serif).italic())
        }
        .foregroundStyle(Paper.muted(scheme))
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 9)
        .overlay(alignment: .bottom) { Rectangle().fill(Paper.rule(scheme)).frame(height: 1) }
    }
}

/// "— The War of the Worlds"
struct Citation: View {
    let title: String
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        if !title.isEmpty {
            Text("— \(title)")
                .font(.system(size: 14, design: .serif).italic())
                .foregroundStyle(Paper.muted(scheme))
                .lineLimit(1)
        }
    }
}

enum CardText {
    /// A window of words around the target so long sentences fit on a card.
    /// Port of excerpt() in web/js/views/flashcards.js; offsets are UTF-16.
    static func excerpt(sentence: String, word: String, offset: Int, radius: Int = 9) -> (text: String, offset: Int?) {
        let ns = sentence as NSString
        let wlen = (word as NSString).length
        var off = offset
        if off < 0 || off + wlen > ns.length || ns.substring(with: NSRange(location: off, length: wlen)) != word {
            off = ns.range(of: word).location
        }
        guard off != NSNotFound else { return (sentence, nil) }
        let regex = try! NSRegularExpression(pattern: "\\S+")
        let tokens = regex.matches(in: sentence, range: NSRange(location: 0, length: ns.length)).map(\.range)
        guard let idx = tokens.firstIndex(where: { off >= $0.location && off < $0.upperBound }),
              tokens.count > radius * 2 + 4 else { return (sentence, off) }
        let a = max(0, idx - radius), b = min(tokens.count, idx + radius + 1)
        let start = tokens[a].location, end = tokens[b - 1].upperBound
        let pre = a > 0 ? "… " : ""
        var body = ns.substring(with: NSRange(location: start, length: end - start))
        if let last = body.last, ",;:".contains(last) { body.removeLast() }
        let text = pre + body + (b < tokens.count ? " …" : "")
        return (text, off - start + (pre as NSString).length)
    }

    /// Quoted sentence with the word bold over a warm marker.
    static func quoted(_ text: String, word: String, offset: Int?, ink: Color) -> AttributedString {
        var out = AttributedString("“\(text)”")
        let ns = text as NSString
        let wlen = (word as NSString).length
        var r = NSRange(location: offset ?? -1, length: wlen)
        if r.location < 0 || r.upperBound > ns.length || ns.substring(with: r) != word { r = ns.range(of: word) }
        let shifted = NSRange(location: r.location + 1, length: r.length) // after the opening quote
        let full = "“\(text)”"
        if r.location != NSNotFound, let range = Range(shifted, in: full),
           let lo = AttributedString.Index(range.lowerBound, within: out),
           let hi = AttributedString.Index(range.upperBound, within: out) {
            out[lo..<hi].font = .system(size: 18, weight: .semibold, design: .serif)
            out[lo..<hi].backgroundColor = Paper.marker
            out[lo..<hi].foregroundColor = ink
        }
        return out
    }
}
