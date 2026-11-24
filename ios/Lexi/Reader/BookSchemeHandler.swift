import Foundation
import UniformTypeIdentifiers
import WebKit

/// Serves the reader page and unzipped books to the web view under `lexi://app/`.
///   /reader.html, /reader.js, /reader.css, /fonts/<file>  → app bundle
///   /book/<folder>/<path>                                  → Application Support/Books
/// Everything shares one origin, so the page can `fetch` chapter files.
final class BookSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "lexi"
    static let pageURL = URL(string: "lexi://app/reader.html")!

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url, let fileURL = resolve(url), let data = try? Data(contentsOf: fileURL) else {
            let resp = HTTPURLResponse(url: task.request.url ?? Self.pageURL, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!
            task.didReceive(resp)
            task.didFinish()
            return
        }
        let mime = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        let headers = ["Content-Type": mime, "Content-Length": String(data.count), "Cache-Control": "no-cache"]
        task.didReceive(HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    private func resolve(_ url: URL) -> URL? {
        let parts = url.path.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }
        guard let first = parts.first else { return nil }
        switch first {
        case "book" where parts.count >= 3:
            let root = MainActor.assumeIsolated { LibraryStore.booksDirectory }.standardizedFileURL
            let file = parts.dropFirst().reduce(root) { $0.appendingPathComponent($1) }.standardizedFileURL
            // Never serve anything outside the books directory.
            return file.path.hasPrefix(root.path + "/") ? file : nil
        case "fonts":
            return parts.last.flatMap { Bundle.main.url(forResource: $0, withExtension: nil) }
        default:
            return parts.count == 1 ? Bundle.main.url(forResource: first, withExtension: nil) : nil
        }
    }
}
