import Testing
@testable import AsciiDocCore
import Foundation

@Suite struct PreprocessorTests {
    private let fm = FileManager.default

    @Test func include_inserts_file_content() throws {
        let tempDir = try temporaryDirectory()
        defer { try? fm.removeItem(at: tempDir) }

        let includeURL = tempDir.appendingPathComponent("child.adoc")
        try "Child paragraph".write(to: includeURL, atomically: true, encoding: .utf8)

        let options = Preprocessor.Options(
            sourceURL: tempDir.appendingPathComponent("main.adoc")
        )

        let preprocessor = Preprocessor(options: options)
        let result = preprocessor.process(
            text: "include::child.adoc[]",
            attributes: [:]
        )

        #expect(result.source.text == "Child paragraph")
        let origin = result.source.lineOrigins.first?.frames.last
        #expect(origin?.file == includeURL.path)
    }

    @Test func escaped_include_remains_literal() throws {
        let tempDir = try temporaryDirectory()
        defer { try? fm.removeItem(at: tempDir) }

        let options = Preprocessor.Options(
            sourceURL: tempDir.appendingPathComponent("main.adoc")
        )
        let text = "\\include::ignored.adoc[]"
        let preprocessor = Preprocessor(options: options)
        let result = preprocessor.process(text: text, attributes: [:])

        #expect(result.source.text == "include::ignored.adoc[]")
    }

    @Test func conditionals_respect_attributes() throws {
        let tempDir = try temporaryDirectory()
        defer { try? fm.removeItem(at: tempDir) }

        let options = Preprocessor.Options(
            sourceURL: tempDir.appendingPathComponent("doc.adoc")
        )
        let text = """
        :feature: yes
        ifdef::feature[]
        enabled
        endif::[]
        ifndef::missing[]
        missing
        endif::[]
        ifdef::missing[]
        skipped
        endif::[]
        """

        let result = Preprocessor(options: options).process(text: text, attributes: [:])
        let lines = result.source.text.split(separator: "\n").map(String.init)
        #expect(lines.contains(":feature: yes"))
        #expect(lines.contains("enabled"))
        #expect(lines.contains("missing"))
        #expect(!lines.contains("skipped"))
    }

    @Test func include_respects_leveloffset_and_indent() throws {
        let tempDir = try temporaryDirectory()
        defer { try? fm.removeItem(at: tempDir) }

        let includeURL = tempDir.appendingPathComponent("section.adoc")
        try "== Child\ncontent".write(to: includeURL, atomically: true, encoding: .utf8)

        let options = Preprocessor.Options(
            sourceURL: tempDir.appendingPathComponent("main.adoc")
        )
        let text = "include::section.adoc[leveloffset=+1,indent=2]"
        let result = Preprocessor(options: options).process(text: text, attributes: [:])
        let lines = result.source.text.split(separator: "\n").map(String.init)

        #expect(lines.first == "=== Child")
        #expect(lines.dropFirst().first == "  content")
    }

    @Test func include_with_lines_and_tags() throws {
        let tempDir = try temporaryDirectory()
        defer { try? fm.removeItem(at: tempDir) }

        let includeURL = tempDir.appendingPathComponent("snippet.adoc")
        let content = """
        one
        // tag::keep[]
        two
        // end::keep[]
        three
        """
        try content.write(to: includeURL, atomically: true, encoding: .utf8)

        let options = Preprocessor.Options(
            sourceURL: tempDir.appendingPathComponent("main.adoc")
        )

        let tagResult = Preprocessor(options: options).process(
            text: "include::snippet.adoc[tags=keep]",
            attributes: [:]
        )
        #expect(tagResult.source.text == "two")

        let lineResult = Preprocessor(options: options).process(
            text: "include::snippet.adoc[lines=2..3]",
            attributes: [:]
        )
        #expect(lineResult.source.text == "// tag::keep[]\ntwo")
    }

    private func temporaryDirectory() throws -> URL {
        let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
}
