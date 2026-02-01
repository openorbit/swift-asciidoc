//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

import Testing
import Foundation
import AsciiDocCore
import AsciiDocAntora



@Suite final class AntoraTestsSuite {
    let tempDir: URL
    
    init() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }
    
    deinit {
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    @Test func testComponentScanning() throws {
        // Setup component structure
        let antoraYml = """
        name: test-component
        version: 1.0.0
        title: Test Component
        nav:
        - modules/ROOT/nav.adoc
        """
        try antoraYml.write(to: tempDir.appendingPathComponent("antora.yml"), atomically: true, encoding: .utf8)
        
        let modulesDir = tempDir.appendingPathComponent("modules")
        let rootDir = modulesDir.appendingPathComponent("ROOT")
        let pagesDir = rootDir.appendingPathComponent("pages")
        let partialsDir = rootDir.appendingPathComponent("partials")
        
        try FileManager.default.createDirectory(at: pagesDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: partialsDir, withIntermediateDirectories: true)
        
        let indexAdoc = "Index Page"
        try indexAdoc.write(to: pagesDir.appendingPathComponent("index.adoc"), atomically: true, encoding: .utf8)
        
        let headerAdoc = "Header Content"
        try headerAdoc.write(to: partialsDir.appendingPathComponent("header.adoc"), atomically: true, encoding: .utf8)
        
        // Scan
        let component = try AntoraComponent(directory: tempDir)
        
        #expect(component.config.name == "test-component")
        
        // Verify Index
        let modules = component.index.modules
        #expect(modules["ROOT"] != nil)
        #expect(modules["ROOT"]?["pages"]?["index.adoc"] != nil)
        #expect(modules["ROOT"]?["partials"]?["header.adoc"] != nil)
    }
    
    @Test func testIncludeResolver() throws {
        // Setup similar to above
        let antoraYml = "name: test\nversion: 1.0"
        try antoraYml.write(to: tempDir.appendingPathComponent("antora.yml"), atomically: true, encoding: .utf8)
        
        let partialsDir = tempDir.appendingPathComponent("modules/ROOT/partials")
        try FileManager.default.createDirectory(at: partialsDir, withIntermediateDirectories: true)
        try "Available".write(to: partialsDir.appendingPathComponent("snippet.adoc"), atomically: true, encoding: .utf8)
        
        let component = try AntoraComponent(directory: tempDir)
        let resolver = LocalAntoraIncludeResolver(component: component)
        
        // Test resolve module:family$resource
        let result = resolver.resolve(target: "ROOT:partials$snippet.adoc", from: nil)
        #expect(result != nil)
        #expect(result?.content == "Available")
        
        // Test "ROOT:partials$snippet.adoc" -> module="ROOT", family="partials"
        let res2 = resolver.resolve(target: "ROOT:partials$snippet.adoc", from: tempDir)
        #expect(res2?.content == "Available")
    }
    
    @Test func testXrefResolver() throws {
        let antoraYml = "name: test\nversion: 1.0"
        try antoraYml.write(to: tempDir.appendingPathComponent("antora.yml"), atomically: true, encoding: .utf8)
        
        let pagesDir = tempDir.appendingPathComponent("modules/ROOT/pages")
        try FileManager.default.createDirectory(at: pagesDir, withIntermediateDirectories: true)
        try "Target Page".write(to: pagesDir.appendingPathComponent("other.adoc"), atomically: true, encoding: .utf8)
        
        let component = try AntoraComponent(directory: tempDir)
        let resolver = LocalAntoraXrefResolver(component: component)
        
        // Parse raw target - ROOT module, implicit pages family
        let target = AdocXrefTarget(raw: "ROOT:other.adoc")
        let href = resolver.resolve(target: target, source: nil)
        
        // Expect: /other.html
        #expect(href == "/other.html")
    }
    
    @Test func testNavigationTree() throws {
        let navContent = """
        * xref:ROOT:index.adoc[Home]
        ** xref:ROOT:about.adoc[About]
        * Link To External
        """
        let navFile = tempDir.appendingPathComponent("nav.adoc")
        try navContent.write(to: navFile, atomically: true, encoding: .utf8)
        
        let pagesDir = tempDir.appendingPathComponent("modules/ROOT/pages")
        try FileManager.default.createDirectory(at: pagesDir, withIntermediateDirectories: true)
        try "".write(to: pagesDir.appendingPathComponent("index.adoc"), atomically: true, encoding: .utf8)
        try "".write(to: pagesDir.appendingPathComponent("about.adoc"), atomically: true, encoding: .utf8)
        try "name: test".write(to: tempDir.appendingPathComponent("antora.yml"), atomically: true, encoding: .utf8)
        
        let component = try AntoraComponent(directory: tempDir)
        let resolver = LocalAntoraXrefResolver(component: component)
        
        let tree = NavigationTree.parse(file: navFile, resolver: resolver)
        
        #expect(tree.roots.count == 2)
        
        guard tree.roots.count >= 2 else { return }
        
        #expect(tree.roots[0].label == "Home")
        #expect(tree.roots[0].href == "/index.html")
        #expect(tree.roots[0].children.count == 1)
        
        guard tree.roots[0].children.count >= 1 else { return }
        
        #expect(tree.roots[0].children[0].label == "About")
        #expect(tree.roots[0].children[0].href == "/about.html")
        
        #expect(tree.roots[1].label == "Link To External")
    }
}
