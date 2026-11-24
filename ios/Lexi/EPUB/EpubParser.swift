import Foundation

/// One entry in a book's table of contents.
struct TocEntry: Codable, Hashable, Identifiable {
    var label: String
    var href: String          // path inside the EPUB, may include #fragment
    var fragment: String?
    var spineIndex: Int
    var level: Int
    var id: String { "\(spineIndex)|\(href)|\(label)" }
}

struct EpubPackage {
    var title: String
    var author: String
    var language: String
    var identifier: String
    var opfPath: String
    var spine: [String]       // chapter paths inside the EPUB, in reading order
    var toc: [TocEntry]
    var coverPath: String?
}

enum EpubError: LocalizedError {
    case notZip, noPackage, malformedPackage, noChapters, missing(String)

    var errorDescription: String? {
        switch self {
        case .notZip: "This file is not a valid EPUB (it could not be unzipped)."
        case .noPackage: "This EPUB has no package document."
        case .malformedPackage: "The EPUB package document is malformed."
        case .noChapters: "This EPUB has no readable chapters."
        case .missing(let p): "Missing file in EPUB: \(p)"
        }
    }
}

/// EPUB 2/3 parser over an unzipped book folder. Ported from web/js/epub/parser.js:
/// container.xml → OPF (metadata, manifest, spine, cover) → nav.xhtml or NCX.
struct EpubParser {
    let root: URL

    private struct ManifestItem { var id: String; var href: String; var mediaType: String; var properties: [String] }

    func data(_ path: String) throws -> Data {
        let url = root.appendingPathComponent(path)
        guard let d = try? Data(contentsOf: url) else { throw EpubError.missing(path) }
        return d
    }

    func parse() throws -> EpubPackage {
        guard let container = XMLTree.parse(try data("META-INF/container.xml")),
              let rootfile = container.descendants("rootfile").first,
              let opfPath = rootfile.attr("full-path") else { throw EpubError.noPackage }
        guard let opf = XMLTree.parse(try data(opfPath)) else { throw EpubError.malformedPackage }

        // Metadata
        let meta = opf.first("metadata") ?? opf
        func dc(_ name: String) -> [String] {
            meta.descendants(name).map { $0.textContent.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }

        // Manifest
        var manifest: [String: ManifestItem] = [:]
        var manifestOrder: [ManifestItem] = []
        for item in opf.descendants("item") {
            let id = item.attr("id") ?? ""
            let m = ManifestItem(
                id: id,
                href: Self.resolvePath(base: opfPath, rel: item.attr("href") ?? ""),
                mediaType: item.attr("media-type") ?? "",
                properties: (item.attr("properties") ?? "").split(separator: " ").map(String.init))
            manifest[id] = m
            manifestOrder.append(m)
        }

        // Spine
        let spineEl = opf.first("spine")
        let spine = (spineEl ?? opf).descendants("itemref")
            .compactMap { manifest[$0.attr("idref") ?? ""] }
            .filter { $0.mediaType.contains("html") || $0.mediaType.contains("xml") }
            .map(\.href)
        guard !spine.isEmpty else { throw EpubError.noChapters }
        var spineIndexByHref: [String: Int] = [:]
        for (i, h) in spine.enumerated() where spineIndexByHref[h] == nil { spineIndexByHref[h] = i }

        // Cover
        let coverMetaId = meta.descendants("meta").first { $0.attr("name") == "cover" }?.attr("content")
        let coverItem = manifestOrder.first { $0.properties.contains("cover-image") }
            ?? coverMetaId.flatMap { manifest[$0] }
            ?? manifestOrder.first { $0.mediaType.hasPrefix("image/") && ($0.id + $0.href).lowercased().contains("cover") }
        let coverPath = coverItem.flatMap { $0.mediaType.hasPrefix("image/") ? $0.href : nil }

        // Table of contents
        func entry(_ label: String, _ href: String, _ level: Int) -> TocEntry? {
            let parts = href.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            guard let idx = spineIndexByHref[parts[0]] else { return nil }
            let clean = label.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            return TocEntry(label: clean.isEmpty ? "Untitled" : clean, href: href,
                            fragment: parts.count > 1 && !parts[1].isEmpty ? parts[1] : nil, spineIndex: idx, level: level)
        }

        var toc: [TocEntry] = []
        if let nav = manifestOrder.first(where: { $0.properties.contains("nav") }) { toc = parseNav(nav.href, entry) }
        if toc.isEmpty {
            let ncx = spineEl?.attr("toc").flatMap { manifest[$0] } ?? manifestOrder.first { $0.mediaType == "application/x-dtbncx+xml" }
            if let ncx { toc = parseNcx(ncx.href, entry) }
        }
        if toc.isEmpty {
            toc = spine.enumerated().map { TocEntry(label: "Section \($0.offset + 1)", href: $0.element, fragment: nil, spineIndex: $0.offset, level: 0) }
        }

        return EpubPackage(
            title: dc("title").first ?? "Untitled",
            author: dc("creator").joined(separator: ", "),
            language: dc("language").first ?? "en",
            identifier: dc("identifier").first ?? "",
            opfPath: opfPath, spine: spine, toc: toc, coverPath: coverPath)
    }

    private func parseNav(_ path: String, _ entry: (String, String, Int) -> TocEntry?) -> [TocEntry] {
        guard let d = try? data(path), let doc = XMLTree.parse(d) else { return [] }
        let navs = doc.descendants("nav")
        guard let nav = navs.first(where: { ($0.attr("type") ?? "").contains("toc") }) ?? navs.first,
              let ol = nav.first("ol") else { return [] }
        var out: [TocEntry] = []
        func walk(_ ol: XMLElement, _ level: Int) {
            for li in ol.childElements("li") {
                if let a = li.children.first(where: { $0.name == "a" || $0.name == "span" }), let href = a.attr("href"),
                   let e = entry(a.textContent, Self.resolvePath(base: path, rel: href), level) {
                    out.append(e)
                }
                if let sub = li.childElements("ol").first { walk(sub, level + 1) }
            }
        }
        walk(ol, 0)
        return out
    }

    private func parseNcx(_ path: String, _ entry: (String, String, Int) -> TocEntry?) -> [TocEntry] {
        guard let d = try? data(path), let doc = XMLTree.parse(d), let navMap = doc.first("navMap") else { return [] }
        var out: [TocEntry] = []
        func walk(_ parent: XMLElement, _ level: Int) {
            for np in parent.childElements("navPoint") {
                let label = np.first("text")?.textContent ?? ""
                if let src = np.first("content")?.attr("src"), let e = entry(label, Self.resolvePath(base: path, rel: src), level) {
                    out.append(e)
                }
                walk(np, level + 1)
            }
        }
        walk(navMap, 0)
        return out
    }

    /// Character count of each chapter's body text, used for whole-book progress.
    func textLengths(_ spine: [String]) -> [Int] {
        spine.map { path in
            guard let d = try? data(path), var s = String(data: d, encoding: .utf8) else { return 1 }
            if let r = s.range(of: "<body", options: .caseInsensitive) { s = String(s[r.lowerBound...]) }
            s = s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            s = s.replacingOccurrences(of: "&[a-zA-Z#0-9]+;", with: "x", options: .regularExpression)
            s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            return max(1, s.count)
        }
    }

    /// Resolve `rel` against the file path `base` (both inside the EPUB). Keeps a #fragment.
    static func resolvePath(base: String, rel: String) -> String {
        if rel.range(of: "^[a-zA-Z]+:", options: .regularExpression) != nil { return rel }
        let split = rel.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        var parts = base.isEmpty ? [] : Array(base.split(separator: "/", omittingEmptySubsequences: false).dropLast().map(String.init))
        for seg in split[0].split(separator: "/").map(String.init) {
            if seg == ".." { _ = parts.popLast() } else if !seg.isEmpty && seg != "." { parts.append(seg) }
        }
        var out = parts.filter { !$0.isEmpty }.joined(separator: "/")
        out = out.removingPercentEncoding ?? out
        return split.count > 1 ? "\(out)#\(split[1])" : out
    }
}
