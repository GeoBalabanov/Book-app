import UIKit
import XCTest
@testable import Lexi

final class EpubPathTests: XCTestCase {
    func testResolvePath() {
        XCTAssertEqual(EpubParser.resolvePath(base: "OEBPS/content.opf", rel: "text/ch1.xhtml"), "OEBPS/text/ch1.xhtml")
        XCTAssertEqual(EpubParser.resolvePath(base: "OEBPS/text/ch1.xhtml", rel: "../images/a.jpg"), "OEBPS/images/a.jpg")
        XCTAssertEqual(EpubParser.resolvePath(base: "OEBPS/toc.ncx", rel: "ch%201.xhtml#p3"), "OEBPS/ch 1.xhtml#p3")
    }
}

final class FontTests: XCTestCase {
    func testLiterataIsRegistered() {
        let names = UIFont.fontNames(forFamilyName: "Literata")
        print("Literata faces:", names)
        XCTAssertFalse(names.isEmpty, "Bundled Literata should be registered at launch")
    }

    func testThemeFontsExist() {
        for f in ReaderFont.all {
            guard let n = f.uiFontName else { continue }
            XCTAssertNotNil(UIFont(name: n, size: 12), "\(f.name) (\(n)) is not available")
        }
    }
}
