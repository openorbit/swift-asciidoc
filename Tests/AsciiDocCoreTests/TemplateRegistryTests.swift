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
        let layoutURL = layoutDir.appendingPathComponent("layout.xad")
        try "pages[]".write(to: layoutURL, atomically: true, encoding: .utf8)
        defer { try? fileManager.removeItem(at: root) }

        let registry = XADTemplateRegistry(searchPaths: [templatesRoot])
        let (template, warnings) = registry.loadTemplate(named: "default")

        #expect(warnings.isEmpty)
        #expect(template != nil)
    }

    @Test
    func listsTemplatesFromSearchPaths() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let templatesRoot = root.appendingPathComponent("Templates")
        let layoutDir = templatesRoot.appendingPathComponent("xad/demo", isDirectory: true)
        try fileManager.createDirectory(at: layoutDir, withIntermediateDirectories: true)
        let layoutURL = layoutDir.appendingPathComponent("layout.xad")
        try "pages[]".write(to: layoutURL, atomically: true, encoding: .utf8)
        defer { try? fileManager.removeItem(at: root) }

        let registry = XADTemplateRegistry(searchPaths: [templatesRoot])
        let names = registry.listTemplates()

        #expect(names.contains("demo"))
    }
}
