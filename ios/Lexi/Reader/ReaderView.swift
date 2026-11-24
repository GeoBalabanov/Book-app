import SwiftUI

/// Full-screen reader: the paginated web view plus Apple Books–style chrome
/// (close button top-left, scrubber at the bottom, menu button bottom-right).
struct ReaderView: View {
    let book: Book
    /// The device appearance, passed in from outside so the reader's own color
    /// scheme override doesn't feed back into "Auto".
    let systemScheme: ColorScheme
    let onClose: () -> Void

    /// Created once on appear; SwiftUI may call init many times, and each model owns a web view.
    @State private var model: ReaderModel?

    var body: some View {
        if let model {
            ReaderScreen(model: model, systemScheme: systemScheme, onClose: onClose)
        } else {
            let s = SettingsStore.shared.settings
            Color(css: ReaderTheme.named(s.theme).palette(dark: s.isDark(system: systemScheme)).bg)
                .ignoresSafeArea()
                .onAppear { model = ReaderModel(book: book) }
        }
    }
}

private struct ReaderScreen: View {
    @Bindable var model: ReaderModel
    let systemScheme: ColorScheme
    let onClose: () -> Void

    @State private var settingsStore = SettingsStore.shared

    private var settings: ReaderSettings { settingsStore.settings }
    private var isDark: Bool { settings.isDark(system: systemScheme) }
    private var palette: ThemePalette { ReaderTheme.named(settings.theme).palette(dark: isDark) }
    /// Chrome follows the page: light text on dark themes (Quiet light is dark grey).
    private var chromeScheme: ColorScheme { luminance(palette.bg) < 0.5 ? .dark : .light }

    var body: some View {
        ZStack {
            Color(css: palette.bg).ignoresSafeArea()
            ReaderWebView(model: model)
                .ignoresSafeArea()
                .opacity(model.ready ? 1 : 0)

            if !model.ready {
                Text("Opening book…")
                    .font(.subheadline)
                    .foregroundStyle(Color(css: palette.muted))
            }

            chrome
            overlays
        }
        .preferredColorScheme(chromeScheme)
        .statusBarHidden(!model.chromeVisible)
        .persistentSystemOverlays(model.chromeVisible ? .automatic : .hidden)
        .sheet(isPresented: $model.showContents) {
            ContentsSheet(model: model)
        }
        .sheet(item: $model.lookup, onDismiss: { model.lookupDismissed() }) { request in
            LookUpSheet(request: request)
        }
        .onAppear { applyTheme(layoutChange: false) }
        .onChange(of: settings) { old, new in
            let layout = old.theme != new.theme || old.font != new.font || old.fontSize != new.fontSize
                || old.lineHeight != new.lineHeight || old.justify != new.justify
            applyTheme(layoutChange: layout)
        }
        .onChange(of: isDark) { applyTheme(layoutChange: false) }
    }

    private func applyTheme(layoutChange: Bool) {
        model.applyTheme(settings, dark: isDark, layoutChange: layoutChange)
    }

    // MARK: Chrome

    private var chrome: some View {
        VStack(spacing: 0) {
            // Top bar
            ZStack {
                Text(model.book.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(css: palette.muted))
                    .lineLimit(1)
                    .padding(.horizontal, 56)
                HStack {
                    RoundButton(systemName: "xmark", size: 38, palette: palette) {
                        model.close()
                        onClose()
                    }
                    .accessibilityLabel("Back to Library")
                    Spacer()
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .opacity(model.chromeVisible ? 1 : 0)
            .offset(y: model.chromeVisible ? 0 : -6)
            .allowsHitTesting(model.chromeVisible)

            Spacer(minLength: 0)

            // Bottom: scrubber + page info, menu button on the right
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 8) {
                    ScrubBar(value: Binding(
                        get: { model.scrubbing ?? model.progress },
                        set: { model.scrubbing = $0 }),
                        onEnd: { model.commitScrub() },
                        palette: palette)
                        .frame(maxWidth: 420)
                        .opacity(model.chromeVisible ? 1 : 0)
                        .allowsHitTesting(model.chromeVisible)
                    Text(model.ready ? model.pageInfo : " ")
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(Color(css: palette.muted))
                        .lineLimit(1)
                        .frame(minHeight: 15)
                }
                .padding(.horizontal, 76)
                .padding(.bottom, 2)
                .frame(maxWidth: .infinity)

                RoundButton(systemName: "list.bullet", size: 44, palette: palette, shadow: true) {
                    withAnimation(.spring(duration: 0.25)) { model.overlay = model.overlay == .menu ? nil : .menu }
                }
                .accessibilityLabel("Reading menu")
                .padding(.trailing, 16)
                .opacity(model.chromeVisible ? 1 : 0)
                .allowsHitTesting(model.chromeVisible)
            }
        }
        .animation(.easeOut(duration: 0.25), value: model.chromeVisible)
    }

    @ViewBuilder private var overlays: some View {
        switch model.overlay {
        case .menu:
            ReaderMenu(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 16)
                .padding(.bottom, 64)
                .transition(.scale(scale: 0.85, anchor: .bottomTrailing).combined(with: .opacity))
        case .settings, .customize:
            ThemesPanel(model: model, systemScheme: systemScheme)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .transition(.move(edge: .bottom))
        case nil:
            EmptyView()
        }
    }
}

/// A round translucent button like the web reader's `.r-round`.
struct RoundButton: View {
    let systemName: String
    let size: CGFloat
    let palette: ThemePalette
    var shadow = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size > 40 ? 17 : 15, weight: .semibold))
                .foregroundStyle(Color(css: palette.fg))
                .frame(width: size, height: size)
                .background(Color(css: palette.btn), in: Circle())
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Color(css: palette.hairline), lineWidth: 0.5))
                .shadow(color: .black.opacity(shadow ? 0.12 : 0), radius: 7, y: 4)
        }
        .buttonStyle(.plain)
    }
}

/// Thin book-position slider: 3pt track filled in the text color, 14pt thumb.
struct ScrubBar: View {
    @Binding var value: Double
    let onEnd: () -> Void
    let palette: ThemePalette

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let x = CGFloat(value) * w
            ZStack(alignment: .leading) {
                Capsule().fill(Color(css: palette.hairline)).frame(height: 3)
                Capsule().fill(Color(css: palette.fg)).frame(width: max(0, x), height: 3)
                Circle().fill(Color(css: palette.fg)).frame(width: 14, height: 14).offset(x: min(max(0, x - 7), w - 14))
            }
            .frame(height: 22)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in value = min(1, max(0, Double(g.location.x / w))) }
                .onEnded { _ in onEnd() })
        }
        .frame(height: 22)
        .accessibilityElement()
        .accessibilityLabel("Book position")
        .accessibilityValue("\(Int(value * 100)) percent")
    }
}

/// Relative luminance of a CSS color, 0 (black) … 1 (white).
func luminance(_ css: String) -> Double {
    let c = UIColor(Color(css: css))
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    c.getRed(&r, green: &g, blue: &b, alpha: &a)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b
}
