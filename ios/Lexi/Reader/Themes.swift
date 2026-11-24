import SwiftUI
import UIKit

/// Reading fonts. `css` is the font stack used in the reader web view; `uiFont`
/// is used to preview the font in native UI. Ported from web/js/reader/themes.js.
struct ReaderFont: Identifiable {
    let id: String
    let name: String
    let css: String?
    let uiFontName: String?     // PostScript name; nil = system design below
    let systemDesign: Font.Design?

    func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if let n = uiFontName, UIFont(name: n, size: size) != nil { return .custom(n, fixedSize: size).weight(weight) }
        return .system(size: size, weight: weight, design: systemDesign ?? .serif)
    }

    static let all: [ReaderFont] = [
        .init(id: "original", name: "Original", css: nil, uiFontName: nil, systemDesign: nil),
        .init(id: "newyork", name: "New York", css: #"ui-serif, "New York", "Lexi Literata", Georgia, serif"#, uiFontName: nil, systemDesign: .serif),
        .init(id: "literata", name: "Literata", css: #""Lexi Literata", Georgia, serif"#, uiFontName: "Literata-Regular", systemDesign: .serif),
        .init(id: "athelas", name: "Athelas", css: #"Athelas, "Lexi Literata", Georgia, serif"#, uiFontName: "Athelas-Regular", systemDesign: .serif),
        .init(id: "charter", name: "Charter", css: #"Charter, "Lexi Literata", Georgia, serif"#, uiFontName: "Charter-Roman", systemDesign: .serif),
        .init(id: "georgia", name: "Georgia", css: #"Georgia, "Lexi Literata", serif"#, uiFontName: "Georgia", systemDesign: .serif),
        .init(id: "iowan", name: "Iowan", css: #""Iowan Old Style", "Lexi Literata", Georgia, serif"#, uiFontName: "IowanOldStyle-Roman", systemDesign: .serif),
        .init(id: "palatino", name: "Palatino", css: #"Palatino, "Palatino Linotype", "Lexi Literata", serif"#, uiFontName: "Palatino-Roman", systemDesign: .serif),
        .init(id: "sanfrancisco", name: "San Francisco", css: #"-apple-system, "SF Pro Text", system-ui, sans-serif"#, uiFontName: nil, systemDesign: .default),
        .init(id: "seravek", name: "Seravek", css: #"Seravek, "Gill Sans Nova", system-ui, sans-serif"#, uiFontName: "Seravek", systemDesign: .default),
        .init(id: "times", name: "Times New Roman", css: #""Times New Roman", Times, serif"#, uiFontName: "TimesNewRomanPSMT", systemDesign: .serif),
    ]

    static func named(_ id: String) -> ReaderFont { all.first { $0.id == id } ?? all[1] }
}

/// Colors for one appearance of a theme, as CSS color strings (shared with the web view).
struct ThemePalette {
    let bg, fg, muted, chrome, btn, accent, select, hairline: String
    var texture: String? = nil
}

struct ReaderTheme: Identifiable {
    let id: String
    let name: String
    let font: String
    let weight: Int
    let textured: Bool
    let light: ThemePalette
    let dark: ThemePalette

    func palette(dark isDark: Bool) -> ThemePalette { isDark ? dark : light }

    private static let textureLight = #"url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='160' height='160'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='.9' numOctaves='2' stitchTiles='stitch'/%3E%3CfeColorMatrix values='0 0 0 0 0.45 0 0 0 0 0.42 0 0 0 0 0.38 0 0 0 .07 0'/%3E%3C/filter%3E%3Crect width='160' height='160' filter='url(%23n)'/%3E%3C/svg%3E")"#
    private static let textureDark = #"url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='160' height='160'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='.9' numOctaves='2' stitchTiles='stitch'/%3E%3CfeColorMatrix values='0 0 0 0 1 0 0 0 0 1 0 0 0 0 1 0 0 0 .05 0'/%3E%3C/filter%3E%3Crect width='160' height='160' filter='url(%23n)'/%3E%3C/svg%3E")"#

    static let all: [ReaderTheme] = [
        .init(id: "original", name: "Original", font: "newyork", weight: 400, textured: false,
              light: .init(bg: "#ffffff", fg: "#121212", muted: "rgba(0,0,0,.45)", chrome: "rgba(250,250,250,.78)", btn: "rgba(120,120,128,.14)", accent: "rgba(0,0,0,.34)", select: "rgba(0,122,255,.2)", hairline: "rgba(0,0,0,.12)"),
              dark: .init(bg: "#000000", fg: "#e8e8e8", muted: "rgba(255,255,255,.45)", chrome: "rgba(22,22,24,.78)", btn: "rgba(118,118,128,.28)", accent: "rgba(255,255,255,.42)", select: "rgba(10,132,255,.38)", hairline: "rgba(255,255,255,.1)")),
        .init(id: "quiet", name: "Quiet", font: "newyork", weight: 400, textured: false,
              light: .init(bg: "#4a4a4d", fg: "#d4d4d6", muted: "rgba(255,255,255,.42)", chrome: "rgba(64,64,67,.82)", btn: "rgba(255,255,255,.12)", accent: "rgba(255,255,255,.42)", select: "rgba(10,132,255,.38)", hairline: "rgba(255,255,255,.1)"),
              dark: .init(bg: "#1c1c1e", fg: "#a8a8ad", muted: "rgba(255,255,255,.35)", chrome: "rgba(36,36,38,.82)", btn: "rgba(255,255,255,.1)", accent: "rgba(255,255,255,.42)", select: "rgba(10,132,255,.38)", hairline: "rgba(255,255,255,.08)")),
        .init(id: "paper", name: "Paper", font: "charter", weight: 400, textured: true,
              light: .init(bg: "#f1f0ed", fg: "#1d1c1a", muted: "rgba(0,0,0,.45)", chrome: "rgba(236,235,231,.8)", btn: "rgba(100,95,85,.13)", accent: "rgba(0,0,0,.34)", select: "rgba(0,122,255,.2)", hairline: "rgba(0,0,0,.1)", texture: textureLight),
              dark: .init(bg: "#232325", fg: "#d6d4cf", muted: "rgba(255,255,255,.4)", chrome: "rgba(40,40,42,.82)", btn: "rgba(255,255,255,.1)", accent: "rgba(255,255,255,.42)", select: "rgba(10,132,255,.38)", hairline: "rgba(255,255,255,.08)", texture: textureDark)),
        .init(id: "bold", name: "Bold", font: "sanfrancisco", weight: 600, textured: false,
              light: .init(bg: "#ffffff", fg: "#000000", muted: "rgba(0,0,0,.5)", chrome: "rgba(250,250,250,.8)", btn: "rgba(120,120,128,.14)", accent: "rgba(0,0,0,.34)", select: "rgba(0,122,255,.2)", hairline: "rgba(0,0,0,.12)"),
              dark: .init(bg: "#000000", fg: "#ffffff", muted: "rgba(255,255,255,.5)", chrome: "rgba(22,22,24,.8)", btn: "rgba(118,118,128,.28)", accent: "rgba(255,255,255,.42)", select: "rgba(10,132,255,.38)", hairline: "rgba(255,255,255,.1)")),
        .init(id: "calm", name: "Calm", font: "athelas", weight: 400, textured: false,
              light: .init(bg: "#f3e7d0", fg: "#3b2f22", muted: "rgba(59,47,34,.5)", chrome: "rgba(238,226,203,.82)", btn: "rgba(110,85,50,.13)", accent: "rgba(0,0,0,.34)", select: "rgba(0,122,255,.2)", hairline: "rgba(59,47,34,.14)"),
              dark: .init(bg: "#2c241c", fg: "#ddcbb0", muted: "rgba(221,203,176,.48)", chrome: "rgba(48,40,32,.84)", btn: "rgba(221,203,176,.12)", accent: "rgba(255,255,255,.42)", select: "rgba(10,132,255,.38)", hairline: "rgba(221,203,176,.1)")),
        .init(id: "focus", name: "Focus", font: "iowan", weight: 400, textured: false,
              light: .init(bg: "#fffbee", fg: "#1b1b1b", muted: "rgba(0,0,0,.45)", chrome: "rgba(252,247,232,.82)", btn: "rgba(120,110,80,.13)", accent: "rgba(0,0,0,.34)", select: "rgba(0,122,255,.2)", hairline: "rgba(0,0,0,.1)"),
              dark: .init(bg: "#1a1813", fg: "#e6dfcc", muted: "rgba(230,223,204,.45)", chrome: "rgba(34,31,25,.84)", btn: "rgba(230,223,204,.1)", accent: "rgba(255,255,255,.42)", select: "rgba(10,132,255,.38)", hairline: "rgba(230,223,204,.08)")),
    ]

    static func named(_ id: String) -> ReaderTheme { all.first { $0.id == id } ?? all[0] }
}

enum Appearance: String, Codable, CaseIterable { case auto, light, dark }

/// Global reader settings, persisted in UserDefaults.
struct ReaderSettings: Codable, Equatable {
    var theme = "original"
    var appearance: Appearance = .auto
    var font = "original"         // "original" = the theme's own font
    var fontSize: Double = 19     // CSS px
    var lineHeight: Double = 1.5
    var justify = false

    func isDark(system: ColorScheme) -> Bool {
        switch appearance {
        case .dark: true
        case .light: false
        case .auto: system == .dark
        }
    }

    /// CSS custom properties for the reader page, same names as the web app.
    func cssVars(dark: Bool) -> [String: String] {
        let t = ReaderTheme.named(theme)
        let p = t.palette(dark: dark)
        let fontKey = font == "original" ? t.font : font
        return [
            "--r-bg": p.bg, "--r-fg": p.fg, "--r-muted": p.muted, "--r-chrome": p.chrome,
            "--r-btn": p.btn, "--r-accent": p.accent, "--r-select": p.select, "--r-hairline": p.hairline,
            "--r-texture": p.texture ?? "none",
            "--r-font": ReaderFont.named(fontKey).css ?? ReaderFont.named("newyork").css!,
            "--r-weight": String(t.weight),
            "--r-size": "\(Int(fontSize))px", "--r-line": String(lineHeight),
            "--r-align": justify ? "justify" : "start",
        ]
    }
}

@Observable
final class SettingsStore {
    static let shared = SettingsStore()
    private static let key = "lexi.readerSettings"

    var settings: ReaderSettings {
        didSet {
            if let d = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(d, forKey: Self.key) }
        }
    }

    private init() {
        if let d = UserDefaults.standard.data(forKey: Self.key), let s = try? JSONDecoder().decode(ReaderSettings.self, from: d) {
            settings = s
        } else {
            settings = ReaderSettings()
        }
    }
}

extension Color {
    /// Parses "#rrggbb" or "rgba(r,g,b,a)" CSS colors.
    init(css: String) {
        let s = css.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#"), s.count == 7, let v = UInt32(s.dropFirst(), radix: 16) {
            self.init(.sRGB, red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255, blue: Double(v & 0xff) / 255)
            return
        }
        if s.hasPrefix("rgba(") {
            let n = s.dropFirst(5).dropLast().split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            if n.count == 4 {
                self.init(.sRGB, red: n[0] / 255, green: n[1] / 255, blue: n[2] / 255, opacity: n[3])
                return
            }
        }
        self = .gray
    }
}
