import SwiftUI
import OSLog
import WebKit

/// State and web-view bridge for one open book.
@Observable
@MainActor
final class ReaderModel {
    enum Overlay { case menu, settings, customize }

    let book: Book
    let toc: [TocEntry]
    private(set) var webView: WKWebView!

    var ready = false
    var chromeVisible = true
    var overlay: Overlay?
    var showContents = false
    /// The word being looked up; drives the Look Up sheet.
    var lookup: LookupRequest?

    private(set) var chapter = 0
    private(set) var page = 0
    private(set) var pages = 1
    private(set) var progress = 0.0
    var scrubbing: Double?           // book position while dragging the scrubber

    private var lastVars: [String: String] = [:]
    private var savedForms: Set<String> = []
    private var insets = EdgeInsets()
    private let openedAt = Date()
    private var pageLoaded = false
    private var saveTask: Task<Void, Never>?
    private let navDelegate = NavLogger()
    private let gestures = ReaderGestures()

    init(book: Book) {
        self.book = book
        self.toc = book.toc
        self.chromeVisible = !book.hasLocation
        self.progress = book.progress
        self.chapter = book.locationChapter
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(BookSchemeHandler(), forURLScheme: BookSchemeHandler.scheme)
        config.userContentController.add(MessageProxy(self), name: "lexi")
        // No WebKit selection, loupe or edit menu: lookups come from our own long-press.
        config.preferences.isTextInteractionEnabled = false
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.scrollView.isScrollEnabled = false
        wv.scrollView.contentInsetAdjustmentBehavior = .never
        wv.scrollView.bounces = false
        wv.allowsLinkPreview = false
        wv.isOpaque = false
        wv.backgroundColor = .clear
        #if DEBUG
        if #available(iOS 16.4, *) { wv.isInspectable = true }
        #endif
        webView = wv
        wv.navigationDelegate = navDelegate
        gestures.attach(to: wv, model: self)
        wv.load(URLRequest(url: BookSchemeHandler.pageURL))
    }

    // MARK: Derived

    var chapterTitle: String {
        var label = ""
        for t in toc { if t.spineIndex <= chapter { label = t.label } else { break } }
        return label
    }

    var currentTocEntry: TocEntry? { toc.last { $0.spineIndex <= chapter } }

    var pageInfo: String {
        if let s = scrubbing {
            let label = toc.last { $0.spineIndex <= chapterFor(progress: s) }?.label
            return [label, "\(Int((s * 100).rounded()))%"].compactMap { $0 }.joined(separator: " · ")
        }
        let left = pages - 1 - page
        let base = left == 0 ? "Last page in chapter" : "\(left) \(left == 1 ? "page" : "pages") left in chapter"
        return chromeVisible ? "\(base) · \(Int((progress * 100).rounded()))%" : base
    }

    private func chapterFor(progress p: Double) -> Int {
        let total = max(1, book.textLengths.reduce(0, +))
        let target = p * Double(total)
        var acc = 0.0
        for (i, l) in book.textLengths.enumerated() {
            if acc + Double(l) >= target { return i }
            acc += Double(l)
        }
        return max(0, book.textLengths.count - 1)
    }

    // MARK: Commands

    func applyTheme(_ settings: ReaderSettings, dark: Bool, layoutChange: Bool) {
        let vars = settings.cssVars(dark: dark)
        let textured = ReaderTheme.named(settings.theme).textured
        guard vars != lastVars || layoutChange else { return }
        lastVars = vars
        guard pageLoaded else { return }   // Lexi.open picks up lastVars
        call("Lexi.setTheme(\(json(vars)), \(textured), \(layoutChange))")
    }

    func toggleChrome() {
        if overlay != nil { overlay = nil; return }
        withAnimation(.easeOut(duration: 0.25)) { chromeVisible.toggle() }
    }

    // MARK: Touch (forwarded from ReaderGestures)

    func tap(at p: CGPoint) {
        guard ready else { return }
        if overlay != nil { withAnimation(.easeOut(duration: 0.2)) { overlay = nil }; return }
        call("Lexi.tap(\(p.x), \(p.y))")
    }

    func dragBegan() {
        if overlay != nil { withAnimation(.easeOut(duration: 0.2)) { overlay = nil } }
        call("Lexi.dragStart()")
    }

    func dragChanged(_ dx: CGFloat) { call("Lexi.dragMove(\(dx))") }

    func dragEnded(_ dx: CGFloat, velocity: CGFloat) { call("Lexi.dragEnd(\(dx), \(velocity / 1000))") }

    func longPress(at p: CGPoint) {
        guard ready else { return }
        if overlay != nil { withAnimation(.easeOut(duration: 0.2)) { overlay = nil }; return }
        call("Lexi.lookupAt(\(p.x), \(p.y))")
    }

    private var insetsJSON: [String: Double] {
        ["top": insets.top, "bottom": insets.bottom, "left": insets.leading, "right": insets.trailing]
    }

    /// The window's safe-area insets, which frame the page margins.
    func setInsets(_ new: EdgeInsets) {
        guard new != insets else { return }
        insets = new
        guard pageLoaded else { return }
        call("Lexi.setInsets(\(json(insetsJSON)))")
    }

    /// Words to underline; sent again whenever the saved list changes.
    func setSavedForms(_ forms: Set<String>) {
        guard forms != savedForms else { return }
        savedForms = forms
        guard pageLoaded else { return }   // Lexi.open sends them
        call("Lexi.setSavedForms(\(json(Array(forms))))")
    }

    func lookupDismissed() {
        call("Lexi.clearLookup()")
    }

    func go(to entry: TocEntry) {
        showContents = false
        call("Lexi.goTo(\(entry.spineIndex), \(json(entry.fragment)))")
        withAnimation { chromeVisible = false }
    }

    func commitScrub() {
        guard let s = scrubbing else { return }
        call("Lexi.goToProgress(\(s))")
        scrubbing = nil
    }

    func close() {
        saveTask?.cancel()
        saveLocation()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "lexi")
    }

    // MARK: Bridge

    fileprivate func handle(_ body: Any) {
        guard let msg = body as? [String: Any], let type = msg["type"] as? String else { return }
        #if DEBUG
        if type != "location" { readerLog("message \(type) \(String(format: "%.2fs", Date().timeIntervalSince(openedAt)))") }
        #endif
        switch type {
        case "loaded":
            pageLoaded = true
            let s = SettingsStore.shared.settings
            let cfg: [String: Any] = [
                "base": "/book/\(book.folder.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? book.folder)/",
                "spine": book.spine,
                "lengths": book.textLengths,
                "chapter": book.hasLocation ? book.locationChapter : 0,
                "fraction": book.hasLocation ? book.locationFraction : 0,
                "vars": lastVars.isEmpty ? s.cssVars(dark: false) : lastVars,
                "textured": ReaderTheme.named(s.theme).textured,
                "savedForms": Array(savedForms),
                "insets": insetsJSON,
            ]
            call("Lexi.open(\(json(cfg)))")
        case "ready":
            withAnimation(.easeOut(duration: 0.2)) { ready = true }
            book.lastOpenedAt = .now
        case "location":
            chapter = msg["chapter"] as? Int ?? 0
            page = msg["page"] as? Int ?? 0
            pages = msg["pages"] as? Int ?? 1
            progress = msg["progress"] as? Double ?? 0
            let fraction = msg["fraction"] as? Double ?? 0
            scheduleSave(fraction: fraction)
        case "lookup":
            guard let word = msg["word"] as? String, let sentence = msg["sentence"] as? String else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            lookup = LookupRequest(word: word, sentence: sentence, offset: msg["offset"] as? Int ?? 0,
                                   bookTitle: book.title, bookID: book.id)
        case "toggleChrome":
            toggleChrome()
        case "dismissOverlay":
            overlay = nil
        case "log":
            #if DEBUG
            readerLog("js: \(msg["message"] ?? "")")
            #endif
        case "openURL":
            if let s = msg["url"] as? String, let url = URL(string: s) { UIApplication.shared.open(url) }
        default:
            break
        }
    }

    private var pendingFraction = 0.0

    private func scheduleSave(fraction: Double) {
        pendingFraction = fraction
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.saveLocation()
        }
    }

    private func saveLocation() {
        guard ready else { return }
        book.hasLocation = true
        book.locationChapter = chapter
        book.locationFraction = pendingFraction
        book.progress = progress
        book.chapterLabel = chapterTitle
        book.lastOpenedAt = .now
        try? book.modelContext?.save()
    }

    func call(_ js: String) {
        webView?.evaluateJavaScript(js) { _, error in
            #if DEBUG
            if let error, (error as NSError).code != 5 { readerLog("JS error for \(js.prefix(60)): \(error)") }
            #endif
        }
    }

    private func json(_ value: Any?) -> String {
        guard let value else { return "null" }
        if let s = value as? String {
            return (try? String(data: JSONSerialization.data(withJSONObject: [s]), encoding: .utf8)).map { String($0.dropFirst().dropLast()) } ?? "null"
        }
        guard let d = try? JSONSerialization.data(withJSONObject: value), let s = String(data: d, encoding: .utf8) else { return "null" }
        return s
    }
}

/// Breaks the retain cycle between WKUserContentController and the model.
private final class MessageProxy: NSObject, WKScriptMessageHandler {
    weak var model: ReaderModel?
    init(_ model: ReaderModel) { self.model = model }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        let body = message.body
        MainActor.assumeIsolated { model?.handle(body) }
    }
}

struct ReaderWebView: UIViewRepresentable {
    let model: ReaderModel
    func makeUIView(context: Context) -> WKWebView { model.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

/// Reloads the page if WebKit's content process dies; logs load failures in debug builds.
private final class NavLogger: NSObject, WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        #if DEBUG
        readerLog("provisional navigation failed: \(error)")
        #endif
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        #if DEBUG
        readerLog("navigation failed: \(error)")
        #endif
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // The page posts "loaded" again and the model re-opens the book at the saved place.
        webView.reload()
    }
}

/// Native tap / horizontal pan / long-press recognisers on the web view. They run
/// alongside WebKit's own recognisers and forward page coordinates (CSS px = points).
@MainActor
final class ReaderGestures: NSObject, UIGestureRecognizerDelegate {
    private weak var model: ReaderModel?
    private weak var view: UIView?

    func attach(to view: UIView, model: ReaderModel) {
        self.model = model
        self.view = view
        let press = UILongPressGestureRecognizer(target: self, action: #selector(onPress(_:)))
        press.minimumPressDuration = 0.43
        let tap = UITapGestureRecognizer(target: self, action: #selector(onTap(_:)))
        tap.require(toFail: press)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(onPan(_:)))
        for g in [press, tap, pan] as [UIGestureRecognizer] {
            g.delegate = self
            g.cancelsTouchesInView = false
            view.addGestureRecognizer(g)
        }
    }

    @objc private func onTap(_ g: UITapGestureRecognizer) {
        guard g.state == .ended else { return }
        model?.tap(at: g.location(in: view))
    }

    @objc private func onPress(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began else { return }
        model?.longPress(at: g.location(in: view))
    }

    @objc private func onPan(_ g: UIPanGestureRecognizer) {
        let dx = g.translation(in: view).x
        switch g.state {
        case .began: model?.dragBegan(); model?.dragChanged(dx)
        case .changed: model?.dragChanged(dx)
        case .ended: model?.dragEnded(dx, velocity: g.velocity(in: view).x)
        case .cancelled, .failed: model?.dragEnded(0, velocity: 0)
        default: break
        }
    }

    func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        guard let pan = g as? UIPanGestureRecognizer else { return true }
        let v = pan.velocity(in: view)
        return abs(v.x) > abs(v.y)
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}

/// Debug logging to the unified log (visible with `log stream --predicate 'subsystem == "lexi"'`).
func readerLog(_ message: @autoclosure () -> String) {
    #if DEBUG
    let text = message()
    Logger(subsystem: "lexi", category: "reader").notice("\(text, privacy: .public)")
    #endif
}
