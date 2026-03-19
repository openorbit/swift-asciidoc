import Testing
@testable import AsciiDocCore
@testable import AsciiDocExtensions

@Suite("Block Macro Resolvers")
struct BlockMacroResolverTests {

    @Test
    func chordResolverProvidesBuiltInStandardVoicing() throws {
        let resolver = MusicBlockMacroResolver()
        let macro = AdocBlockMacro(name: "chord", target: "G")

        let resolved = resolver.resolve(blockMacro: macro, attributes: [:])
        let attributes = try #require(resolved?["attributes"] as? [String: String])

        #expect(attributes["instrument"] == "guitar")
        #expect(attributes["tuning"] == "E A D G B E")
        #expect(attributes["frets"] == "3 2 0 0 0 3")
        #expect(attributes["fingers"] == "2 1 0 0 0 3")
    }

    @Test
    func chordResolverSupportsAlternateTunings() throws {
        let resolver = MusicBlockMacroResolver()
        let macro = AdocBlockMacro(name: "chord", target: "Dsus4")

        let resolved = resolver.resolve(blockMacro: macro, attributes: ["tuning": "dadgad"])
        let attributes = try #require(resolved?["attributes"] as? [String: String])

        #expect(attributes["tuning"] == "D A D G A D")
        #expect(attributes["frets"] == "0 0 0 2 3 3")
    }

    @Test
    func chordResolverLetsExplicitAttributesOverrideLibrary() throws {
        let resolver = MusicBlockMacroResolver()
        let macro = AdocBlockMacro(name: "chord", target: "G")

        let resolved = resolver.resolve(
            blockMacro: macro,
            attributes: [
                "frets": "3 5 5 4 3 3",
                "position": "3"
            ]
        )
        let attributes = try #require(resolved?["attributes"] as? [String: String])

        #expect(attributes["frets"] == "3 5 5 4 3 3")
        #expect(attributes["position"] == "3")
        #expect(attributes["tuning"] == "E A D G B E")
    }
}
