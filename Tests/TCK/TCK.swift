//
//  TCK.swift
//  AsciiDoc-Swift
//
//  Created by Mattias Holm on 2025-11-01.
//

import Testing
@testable import AsciiDocCore
import Foundation

func readTestData(base: String) -> (input: String, expectedOutput: Data) {
  let inputUrl = Bundle.module.url(forResource: "\(base)-input", withExtension: "adoc")
  let expectedOutputUrl = Bundle.module.url(forResource: "\(base)-output", withExtension: "json")

  let input = try! Data(contentsOf: inputUrl!)
  let expectedOutput = try! Data(contentsOf: expectedOutputUrl!)
  let inputString = String(data: input, encoding: .utf8)!
  return (inputString, expectedOutput)
}

private func inlineSpan(for text: Substring) -> AdocRange {
    // Line 1, col 1 → col = text.count (ASCII in TCK inline tests)
    let start = AdocPos(offset: text.startIndex, line: 1, column: 1)
    let endIndex = text.index(before: text.endIndex)
    let end = AdocPos(offset: endIndex, line: 1, column: text.count)
    return AdocRange(start: start, end: end)
}

private func trimTrailingNewlines(_ s: String) -> String {
    var t = s
    while let last = t.last, last == "\n" || last == "\r" {
        t.removeLast()
    }
    return t
}

@Suite("Inline Tests")
struct TCK_Inline {

    @Test func no_markup__single_word_input() {
        let (input, expectedOutput) = readTestData(base: "tests/inline/no-markup/single-word")
        let decoder = JSONDecoder()
        let expected = try! decoder.decode([ASGInline].self, from: expectedOutput)
        let trimmedInput = trimTrailingNewlines(input)

        let span = inlineSpan(for: Substring(trimmedInput))
        let inlines = parseInlines(trimmedInput, baseSpan: span)
        let asg = inlines.toASGInlines()
        expectASGEqual(expected, asg)
        #expect(expected == asg)
    }

    @Test func span__strong__constrained_single_char() {
        let (input, expectedOutput) = readTestData(base: "tests/inline/span/strong/constrained-single-char")
        let decoder = JSONDecoder()
        let expected = try! decoder.decode([ASGInline].self, from: expectedOutput)
        let trimmedInput = trimTrailingNewlines(input)

        let span = inlineSpan(for: Substring(trimmedInput))
        let inlines = parseInlines(trimmedInput, baseSpan: span)
        let asg = inlines.toASGInlines()
        expectASGEqual(expected, asg)
        #expect(expected == asg)
    }
}


@Suite("Block Tests")
struct TCK_Block {
  @Test func document__body_only() {
    let (input, expectedOutput) = readTestData(base: "tests/block/document/body-only")
    let decoder = JSONDecoder()
    let expected = try! decoder.decode(ASGDocument.self, from: expectedOutput)

    let parser = AdocParser()
    let ism = parser.parse(text: input, includeHeaderDerivedAttributes: false)
    let asg = ism.toASG()

    expectASGEqual(expected, asg)

    #expect(expected == asg)
  }

  @Test func document__header_body() {
    let (input, expectedOutput) = readTestData(base: "tests/block/document/header-body")
    let decoder = JSONDecoder()
    let expected = try! decoder.decode(ASGDocument.self, from: expectedOutput)

    let parser = AdocParser()
    let ism = parser.parse(text: input, includeHeaderDerivedAttributes: false)
    let asg = ism.toASG()

    expectASGEqual(expected, asg)
    #expect(expected == asg)
  }

  @Test func header__header_body() {
    let (input, expectedOutput) = readTestData(base: "tests/block/header/attribute-entries-below-title")
    let decoder = JSONDecoder()
    let expected = try! decoder.decode(ASGDocument.self, from: expectedOutput)

    let parser = AdocParser()
    let ism = parser.parse(text: input, includeHeaderDerivedAttributes: false)
    let asg = ism.toASG()

    expectASGEqual(expected, asg)

    #expect(expected == asg)
  }

  @Test func list__unordered__single_item() {
    let (input, expectedOutput) = readTestData(base: "tests/block/list/unordered/single-item")
    let decoder = JSONDecoder()
    let expected = try! decoder.decode(ASGDocument.self, from: expectedOutput)

    let parser = AdocParser()
    let ism = parser.parse(text: input, includeHeaderDerivedAttributes: false)
    let asg = ism.toASG()

    expectASGEqual(expected, asg)

    #expect(expected == asg)
  }

  @Test func listing__multiple_lines() {
    let (input, expectedOutput) = readTestData(base: "tests/block/listing/multiple-lines")
    let decoder = JSONDecoder()
    let expected = try! decoder.decode(ASGDocument.self, from: expectedOutput)

    let parser = AdocParser()
    let ism = parser.parse(text: input, includeHeaderDerivedAttributes: false)
    let asg = ism.toASG()

    expectASGEqual(expected, asg)

    #expect(expected == asg)
  }

  @Test func paragraph__multiple_lines() {
    let (input, expectedOutput) = readTestData(base: "tests/block/paragraph/multiple-lines")
    let decoder = JSONDecoder()
    let expected = try! decoder.decode(ASGDocument.self, from: expectedOutput)

    let parser = AdocParser()
    let ism = parser.parse(text: input, includeHeaderDerivedAttributes: false)
    let asg = ism.toASG()

    expectASGEqual(expected, asg)

    #expect(expected == asg)
  }
  @Test func paragraph__paragraph_empty_lines_paragraph() {
    let (input, expectedOutput) = readTestData(base: "tests/block/paragraph/paragraph-empty-lines-paragraph")
    let decoder = JSONDecoder()
    let expected = try! decoder.decode(ASGDocument.self, from: expectedOutput)

    let parser = AdocParser()
    let ism = parser.parse(text: input, includeHeaderDerivedAttributes: false)
    let asg = ism.toASG()
    #expect(expected == asg)
  }

  @Test func paragraph__sibling_paragraphs() {
    let (input, expectedOutput) = readTestData(base: "tests/block/paragraph/sibling-paragraphs")
    let decoder = JSONDecoder()
    let expected = try! decoder.decode(ASGDocument.self, from: expectedOutput)

    let parser = AdocParser()
    let ism = parser.parse(text: input, includeHeaderDerivedAttributes: false)
    let asg = ism.toASG()

    expectASGEqual(expected, asg)

    #expect(expected == asg)
  }

  @Test func paragraph__single_line() {
    let (input, expectedOutput) = readTestData(base: "tests/block/paragraph/single-line")
    let decoder = JSONDecoder()
    let expected = try! decoder.decode(ASGDocument.self, from: expectedOutput)

    let parser = AdocParser()
    let ism = parser.parse(text: input, includeHeaderDerivedAttributes: false)
    let asg = ism.toASG()
    #expect(expected == asg)
  }

  @Test func section__title_body() {
    let (input, expectedOutput) = readTestData(base: "tests/block/section/title-body")
    let decoder = JSONDecoder()
    let expected = try! decoder.decode(ASGDocument.self, from: expectedOutput)

    let parser = AdocParser()
    let ism = parser.parse(text: input, includeHeaderDerivedAttributes: false)
    let asg = ism.toASG()

    expectASGEqual(expected, asg)

    #expect(expected == asg)
  }

  @Test func sidebar__containing_unordered_list() {
    let (input, expectedOutput) = readTestData(base: "tests/block/sidebar/containing-unordered-list")
    let decoder = JSONDecoder()
    let expected = try! decoder.decode(ASGDocument.self, from: expectedOutput)

    let parser = AdocParser()
    let ism = parser.parse(text: input, includeHeaderDerivedAttributes: false)
    let asg = ism.toASG()

    expectASGEqual(expected, asg)

    #expect(expected == asg)
  }

}
