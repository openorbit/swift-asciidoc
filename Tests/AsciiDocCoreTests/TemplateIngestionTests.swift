import Testing
import Foundation
import AsciiDocPagedRendering

@Suite("XAD Template Ingestion")
struct XADTemplateIngestionTests {
    @Test
    func ingestsLayoutBlockAndAssets() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let templateURL = root.appendingPathComponent("template.adoc")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let source = """
        = Template
        :template.css: template.css, theme.css
        :template.js: template.js

        [layout]
        ----
        pages[]
        ----
        """
        try source.write(to: templateURL, atomically: true, encoding: .utf8)

        let ingestor = XADTemplateIngestor()
        let (template, warnings) = ingestor.ingestTemplate(at: templateURL)

        #expect(warnings.isEmpty)
        #expect(template != nil)
        #expect(template?.layoutProgram != nil)
        #expect(template?.assets.css == ["template.css", "theme.css"])
        #expect(template?.assets.js == ["template.js"])
    }
}
