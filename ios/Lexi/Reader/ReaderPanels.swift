import SwiftUI

// MARK: - Reading menu (bottom-right popover)

struct ReaderMenu: View {
    let model: ReaderModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.chapterTitle.isEmpty ? model.book.title : model.chapterTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(2)
                Text("\(Int((model.progress * 100).rounded()))% of book")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Divider()
            row("Contents", systemImage: "list.bullet") {
                model.overlay = nil
                model.showContents = true
            }
            Divider()
            row("Themes & Settings", systemImage: "textformat") {
                withAnimation(.spring(duration: 0.32, bounce: 0.1)) { model.overlay = .settings }
            }
        }
        .frame(width: 250)
        .background(Color(.systemBackground).opacity(0.78), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 20, y: 12)
    }

    private func row(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).font(.body)
                Spacer()
                Image(systemName: systemImage).font(.system(size: 17))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuRowStyle())
    }
}

struct MenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .background(configuration.isPressed ? Color(.tertiarySystemFill) : .clear)
    }
}

// MARK: - Themes & Settings panel

struct ThemesPanel: View {
    let model: ReaderModel
    let systemScheme: ColorScheme
    @State private var store = SettingsStore.shared
    @State private var brightness = Double(UIScreen.main.brightness)

    private var s: ReaderSettings { store.settings }

    var body: some View {
        VStack(spacing: 14) {
            if model.overlay == .customize { customize } else { main }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .frame(maxWidth: 480)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 14, topTrailingRadius: 14, style: .continuous)
                .fill(Color(.systemBackground).opacity(0.72))
                .background(.ultraThinMaterial, in: UnevenRoundedRectangle(topLeadingRadius: 14, topTrailingRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 20, y: 0)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func head(_ title: String, back: Bool) -> some View {
        ZStack {
            Text(title).font(.headline)
            HStack {
                if back {
                    Button { withAnimation(.easeOut(duration: 0.2)) { model.overlay = .settings } } label: {
                        Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold))
                            .frame(width: 44, height: 40, alignment: .leading)
                    }
                    .accessibilityLabel("Back")
                }
                Spacer()
                CloseCircle { withAnimation(.easeOut(duration: 0.25)) { model.overlay = nil } }
            }
        }
        .foregroundStyle(.primary)
        .frame(minHeight: 40)
    }

    // MARK: Main view

    private var main: some View {
        VStack(spacing: 14) {
            head("Themes & Settings", back: false)
            HStack(spacing: 10) {
                HStack(spacing: 0) {
                    capsuleButton(disabled: s.fontSize <= 14) { store.settings.fontSize = max(14, s.fontSize - 1) } label: {
                        Text("A").font(.system(size: 15, weight: .medium))
                    }
                    .accessibilityLabel("Smaller text")
                    Rectangle().fill(.separator).frame(width: 0.5, height: 22)
                    capsuleButton(disabled: s.fontSize >= 32) { store.settings.fontSize = min(32, s.fontSize + 1) } label: {
                        Text("A").font(.system(size: 23, weight: .medium))
                    }
                    .accessibilityLabel("Larger text")
                }
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                capsuleButton(disabled: false) {
                    let all = Appearance.allCases
                    store.settings.appearance = all[(all.firstIndex(of: s.appearance)! + 1) % all.count]
                } label: {
                    Image(systemName: appearanceIcon).font(.system(size: 19))
                }
                .frame(width: 56)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityLabel(appearanceLabel)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(ReaderTheme.all) { theme in themeTile(theme) }
            }

            Button { withAnimation(.easeOut(duration: 0.2)) { model.overlay = .customize } } label: {
                Label("Customize", systemImage: "slider.horizontal.3")
                    .font(.body.weight(.medium))
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var appearanceIcon: String {
        switch s.appearance { case .auto: "circle.lefthalf.filled"; case .light: "sun.max"; case .dark: "moon" }
    }

    private var appearanceLabel: String {
        switch s.appearance { case .auto: "Appearance: match device"; case .light: "Appearance: light"; case .dark: "Appearance: dark" }
    }

    private func capsuleButton<L: View>(disabled: Bool, action: @escaping () -> Void, @ViewBuilder label: () -> L) -> some View {
        Button(action: action) {
            label().frame(maxWidth: .infinity, minHeight: 46).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
    }

    private func themeTile(_ theme: ReaderTheme) -> some View {
        let dark = s.isDark(system: systemScheme)
        let p = theme.palette(dark: dark)
        let selected = s.theme == theme.id
        return Button {
            store.settings.theme = theme.id
            store.settings.font = "original"
        } label: {
            VStack(spacing: 4) {
                Text("Aa")
                    .font(ReaderFont.named(theme.font).font(size: 28, weight: theme.weight >= 600 ? .semibold : .regular))
                    .frame(height: 34)
                Text(theme.name).font(.system(size: 12, weight: .medium)).opacity(0.85)
            }
            .foregroundStyle(Color(css: p.fg))
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(css: p.bg))
                if theme.textured { PaperGrain(dark: dark).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous)) }
            }
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(selected ? Color.primary : Color.gray.opacity(0.35), lineWidth: selected ? 2 : 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(theme.name) theme")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Customize view

    private var customize: some View {
        VStack(spacing: 14) {
            head("Customize", back: true)

            HStack(spacing: 12) {
                Image(systemName: "sun.min.fill").foregroundStyle(.secondary)
                Slider(value: $brightness, in: 0...1) { Text("Brightness") }
                    .tint(.primary)
                    .onChange(of: brightness) { UIScreen.main.brightness = CGFloat(brightness) }
                Image(systemName: "sun.max.fill").foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 46)
            .background(Color(.quaternarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(spacing: 0) {
                panelRow("Line spacing") {
                    Segmented(items: [(1.35, "Tight"), (1.5, "Normal"), (1.75, "Loose")], selection: s.lineHeight) { store.settings.lineHeight = $0 }
                }
                Divider().padding(.leading, 14)
                panelRow("Justify text") {
                    Segmented(items: [(false, "Off"), (true, "On")], selection: s.justify) { store.settings.justify = $0 }
                }
            }
            .background(Color(.quaternarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            ScrollView {
                VStack(spacing: 0) {
                    let themeFont = ReaderFont.named(ReaderTheme.named(s.theme).font)
                    ForEach(Array(ReaderFont.all.enumerated()), id: \.element.id) { i, f in
                        if i > 0 { Divider().padding(.leading, 14) }
                        Button { store.settings.font = f.id } label: {
                            HStack {
                                Text(f.id == "original" ? "Original (\(themeFont.name))" : f.name)
                                    .font((f.id == "original" ? themeFont : f).font(size: 18))
                                Spacer()
                                if s.font == f.id { Image(systemName: "checkmark").font(.system(size: 14, weight: .semibold)) }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 260)
            .background(Color(.quaternarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func panelRow<C: View>(_ title: String, @ViewBuilder control: () -> C) -> some View {
        HStack {
            Text(title).font(.system(size: 16))
            Spacer()
            control()
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 46)
    }
}

/// Small segmented control styled like the web panel's `.seg`.
struct Segmented<V: Equatable>: View {
    let items: [(V, String)]
    let selection: V
    let onPick: (V) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { i in
                let (v, label) = items[i]
                Button { onPick(v) } label: {
                    Text(label)
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background {
                            if v == selection {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Color(.systemBackground))
                                    .shadow(color: .black.opacity(0.14), radius: 1.5, y: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

/// The grey circular close button used on sheets and panels.
struct CloseCircle: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(Color(.tertiarySystemFill), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
    }
}

/// Faint paper grain for the Paper theme tile (the page itself uses the CSS texture).
struct PaperGrain: View {
    let dark: Bool
    var body: some View {
        Canvas { ctx, size in
            var rng = SeededRandom(seed: 7)
            for _ in 0..<Int(size.width * size.height / 6) {
                let x = Double(rng.next() % 10_000) / 10_000 * size.width
                let y = Double(rng.next() % 10_000) / 10_000 * size.height
                ctx.fill(Path(CGRect(x: x, y: y, width: 1, height: 1)),
                         with: .color((dark ? Color.white : Color(red: 0.45, green: 0.42, blue: 0.38)).opacity(0.08)))
            }
        }
        .allowsHitTesting(false)
    }
}

struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1 }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state >> 33
    }
}

// MARK: - Contents

struct ContentsSheet: View {
    let model: ReaderModel

    var body: some View {
        let current = model.currentTocEntry
        VStack(spacing: 0) {
            SheetHeader(title: model.book.title) { model.showContents = false }
            ScrollViewReader { proxy in
                List(model.toc) { t in
                    let isPart = t.level == 0 && t.label.range(of: "^part\\b", options: [.regularExpression, .caseInsensitive]) != nil
                    let isCurrent = t.id == current?.id
                    Button { model.go(to: t) } label: {
                        HStack {
                            Text(t.label)
                                .font(isPart ? .footnote : (t.level >= 2 ? .subheadline : .body))
                                .fontWeight(isCurrent ? .semibold : .regular)
                                .textCase(isPart ? .uppercase : nil)
                                .foregroundStyle(isPart ? .secondary : .primary)
                            Spacer()
                            if isCurrent { Text("•").foregroundStyle(.secondary) }
                        }
                        .padding(.leading, t.level >= 2 ? 16 : 0)
                        .padding(.top, isPart ? 10 : 0)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .id(t.id)
                }
                .listStyle(.plain)
                .onAppear { if let id = current?.id { proxy.scrollTo(id, anchor: .center) } }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

/// Centered sheet title with a grey close button, like the web app's sheets.
struct SheetHeader: View {
    let title: String
    let onClose: () -> Void
    var body: some View {
        ZStack {
            Text(title).font(.headline).lineLimit(1).padding(.horizontal, 52)
            HStack { Spacer(); CloseCircle(action: onClose) }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }
}
