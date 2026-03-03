import Testing
import Foundation
import AsciiDocPagedRendering

@Suite("XAD Template Registry")
struct XADTemplateRegistryTests {
    @Test
    func loadsTemplateFromSearchPath() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let templatesRoot = root.appendingPathComponent("Templates")
        let layoutDir = templatesRoot.appendingPathComponent("xad/default", isDirectory: true)
        try fileManager.createDirectory(at: layoutDir, withIntermediateDirectories: true)
        let templateURL = layoutDir.appendingPathComponent("template.adoc")
        let template = """
        = Template
        
        [layout]
        ----
        pages[]
        ----
        """
        try template.write(to: templateURL, atomically: true, encoding: .utf8)
        defer { try? fileManager.removeItem(at: root) }

        let registry = XADTemplateRegistry(searchPaths: [templatesRoot])
        let (loadedTemplate, warnings) = registry.loadTemplate(named: "default")

        #expect(warnings.isEmpty)
        #expect(loadedTemplate != nil)
    }

    @Test
    func listsTemplatesFromSearchPaths() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let templatesRoot = root.appendingPathComponent("Templates")
        let layoutDir = templatesRoot.appendingPathComponent("xad/demo", isDirectory: true)
        try fileManager.createDirectory(at: layoutDir, withIntermediateDirectories: true)
        let templateURL = layoutDir.appendingPathComponent("template.adoc")
        let template = """
        = Template
        
        [layout]
        ----
        pages[]
        ----
        """
        try template.write(to: templateURL, atomically: true, encoding: .utf8)
        defer { try? fileManager.removeItem(at: root) }

        let registry = XADTemplateRegistry(searchPaths: [templatesRoot])
        let names = registry.listTemplates()

        #expect(names.contains("demo"))
    }
}
