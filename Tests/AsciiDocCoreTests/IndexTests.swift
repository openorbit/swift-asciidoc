//
//  IndexTests.swift
//  AsciiDoc-Swift
//
//  Created by Mattias Holm on 2025-12-13.
//

import XCTest
@testable import AsciiDocCore
@testable import AsciiDocRender

final class IndexTests: XCTestCase {

    func testParsingVisibleIndexTerm() {
        let text = "This is ((visible))."
        let inlines = parseInlines(text, baseSpan: nil)
        
        // Text("This is "), IndexTerm(terms: ["visible"], visible: true), Text(".")
        XCTAssertEqual(inlines.count, 3)
        
        if case .text(let t, _) = inlines[0] {
            XCTAssertEqual(t, "This is ")
        } else { XCTFail("Expected text") }
        
        if case .indexTerm(let terms, let visible, _) = inlines[1] {
            XCTAssertEqual(terms, ["visible"])
            XCTAssertTrue(visible)
        } else { XCTFail("Expected indexTerm") }
        
        if case .text(let t, _) = inlines[2] {
            XCTAssertEqual(t, ".")
        } else { XCTFail("Expected text") }
    }
    
    func testParsingInvisibleIndexTerm() {
        let text = "Hidden text(((term1, term2)))."
        let inlines = parseInlines(text, baseSpan: nil)
        
        // Text("Hidden text"), IndexTerm(terms: ["term1", "term2"], visible: false), Text(".")
        XCTAssertEqual(inlines.count, 3)
        
        if case .indexTerm(let terms, let visible, _) = inlines[1] {
            XCTAssertEqual(terms, ["term1", "term2"])
            XCTAssertFalse(visible)
        } else { XCTFail("Expected indexTerm") }
    }
    
    func testParsingIndexTermMacro() {
        let text = "Macro indexterm:[term1, term2]"
        let inlines = parseInlines(text, baseSpan: nil)
        
        // Text("Macro "), IndexTerm(...)
        guard inlines.count == 2 else { XCTFail("Count \(inlines.count)"); return }
        
        if case .indexTerm(let terms, let visible, _) = inlines[1] {
            XCTAssertEqual(terms, ["term1", "term2"])
            XCTAssertFalse(visible)
        } else { XCTFail("Expected hidden indexTerm") }
    }
    
    func testParsingIndexTerm2Macro() {
        let text = "Macro indexterm2:[visible one]"
        let inlines = parseInlines(text, baseSpan: nil)
        
        guard inlines.count == 2 else { XCTFail("Count \(inlines.count)"); return }
        
        if case .indexTerm(let terms, let visible, _) = inlines[1] {
            XCTAssertEqual(terms, ["visible one"])
            XCTAssertTrue(visible)
        } else { XCTFail("Expected visible indexTerm") }
    }
}
