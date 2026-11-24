import XCTest
import ZIPFoundation
@testable import Lexi

/// Parses the small fixture EPUB (two Aesop fables, retold; public domain),
/// the same file used to test importing from Files in the Simulator.
final class EpubParserTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        let epub = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "fables", withExtension: "epub"))
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.unzipItem(at: epub, to: dir)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testMetadataSpineTocAndCover() throws {
        let parser = EpubParser(root: dir)
        let pkg = try parser.parse()
        XCTAssertEqual(pkg.title, "Fables of Aesop")
        XCTAssertEqual(pkg.author, "Aesop")
        XCTAssertEqual(pkg.spine, ["OEBPS/fox.xhtml", "OEBPS/ant.xhtml"])
        XCTAssertEqual(pkg.toc.map(\.label), ["The Fox and the Grapes", "The Ant and the Grasshopper"])
        XCTAssertEqual(pkg.toc.map(\.spineIndex), [0, 1])
        XCTAssertEqual(pkg.coverPath, "OEBPS/cover.svg")

        let lengths = parser.textLengths(pkg.spine)
        XCTAssertEqual(lengths.count, 2)
        XCTAssertTrue(lengths.allSatisfy { $0 > 300 }, "\(lengths)")
    }
}
