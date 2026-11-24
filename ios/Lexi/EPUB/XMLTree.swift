import Foundation

/// A tiny read-only XML tree built with `XMLParser`. Enough to walk
/// container.xml, the OPF package, nav.xhtml and NCX documents by local name.
final class XMLElement {
    let name: String            // local name, e.g. "item"
    let attributes: [String: String]
    private(set) var children: [XMLElement] = []
    fileprivate(set) var text = ""
    weak var parent: XMLElement?

    init(name: String, attributes: [String: String]) {
        self.name = name
        self.attributes = attributes
    }

    fileprivate func append(_ child: XMLElement) {
        child.parent = self
        children.append(child)
    }

    /// Attribute by qualified or local name ("epub:type" also matches "type" with a prefix).
    func attr(_ key: String) -> String? {
        if let v = attributes[key] { return v }
        return attributes.first { $0.key.split(separator: ":").last.map(String.init) == key }?.value
    }

    /// All text content below this element, in document order.
    var textContent: String {
        children.isEmpty ? text : text + children.map(\.textContent).joined()
    }

    /// Depth-first search for descendants with this local name.
    func descendants(_ name: String) -> [XMLElement] {
        var out: [XMLElement] = []
        for c in children {
            if c.name == name { out.append(c) }
            out.append(contentsOf: c.descendants(name))
        }
        return out
    }

    func first(_ name: String) -> XMLElement? {
        for c in children {
            if c.name == name { return c }
            if let d = c.first(name) { return d }
        }
        return nil
    }

    func childElements(_ name: String) -> [XMLElement] { children.filter { $0.name == name } }
}

enum XMLTree {
    /// Parse XML or XHTML. HTML named entities (&nbsp; etc.) that plain XML
    /// rejects are replaced before parsing.
    static func parse(_ data: Data) -> XMLElement? {
        if let root = parseStrict(data) { return root }
        guard var s = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return nil }
        for (entity, value) in htmlEntities { s = s.replacingOccurrences(of: "&\(entity);", with: value) }
        return parseStrict(Data(s.utf8))
    }

    private static func parseStrict(_ data: Data) -> XMLElement? {
        let builder = Builder()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = builder
        guard parser.parse() else { return nil }
        return builder.root.children.first
    }

    private static let htmlEntities: [(String, String)] = [
        ("nbsp", "\u{00A0}"), ("mdash", "—"), ("ndash", "–"), ("hellip", "…"), ("rsquo", "’"), ("lsquo", "‘"),
        ("rdquo", "”"), ("ldquo", "“"), ("copy", "©"), ("eacute", "é"), ("egrave", "è"), ("aacute", "á"), ("shy", "\u{00AD}"),
    ]

    private final class Builder: NSObject, XMLParserDelegate {
        let root = XMLElement(name: "#document", attributes: [:])
        private var stack: [XMLElement] = []

        override init() { super.init(); stack = [root] }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            let el = XMLElement(name: elementName, attributes: attributeDict)
            stack.last?.append(el)
            stack.append(el)
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            stack.removeLast()
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard let cur = stack.last else { return }
            // Keep text in order relative to children by attaching it to a text node.
            let t = XMLElement(name: "#text", attributes: [:])
            t.text = string
            cur.append(t)
        }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            if let s = String(data: CDATABlock, encoding: .utf8) { self.parser(parser, foundCharacters: s) }
        }
    }
}
