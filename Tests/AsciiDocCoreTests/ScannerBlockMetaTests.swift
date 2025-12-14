import Testing
@testable import AsciiDocCore

@Suite("Scanner Blcok Meta")
struct ScannerBlockMetaTests {


    private func firstBlockMeta(_ src: String) -> LineTok? {
        LineScanner().scan(src).map(\.kind).first { if case .blockMeta = $0 { return true } else { return false } }
    }

    @Test
    func blockmeta_id_only() {
        let tok = firstBlockMeta("[#intro]")!
        if case .blockMeta(_, let id, let roles, let opts) = tok {
            #expect(id != nil)
            #expect(roles.isEmpty)
            #expect(opts.isEmpty)
        } else { #expect(Bool(false), "Expected blockMeta") }
    }

    @Test
    func blockmeta_id_roles_options_mixed() {
        let tok = firstBlockMeta("[#intro.role1.role2%optA%optB]")!
        if case .blockMeta(_, let id, let roles, let opts) = tok {
            #expect(id != nil)
            #expect(roles.count == 2)
            #expect(opts.count == 2)
        } else { #expect(Bool(false), "Expected blockMeta") }
    }

    @Test
    func blockmeta_with_attrs_after_comma() {
        let tok = firstBlockMeta("[#tbl,cols=3*,format=csv]")!
        if case .blockMeta(_, let id, let roles, let opts) = tok {
            #expect(id != nil)
            #expect(roles.isEmpty)
            #expect(opts.isEmpty)
        } else { #expect(Bool(false), "Expected blockMeta") }
    }

    @Test
    func blockmeta_roles_only() {
        let tok = firstBlockMeta("[.lead.hero]")!
        if case .blockMeta(_, let id, let roles, let opts) = tok {
            #expect(id == nil)
            #expect(roles.count == 2)
            #expect(opts.isEmpty)
        } else { #expect(Bool(false), "Expected blockMeta") }
    }

    @Test
    func blockmeta_options_only() {
        let tok = firstBlockMeta("[%hardbreaks%step]")!
        if case .blockMeta(_, let id, let roles, let opts) = tok {
            #expect(id == nil)
            #expect(roles.isEmpty)
            #expect(opts.count == 2)
        } else { #expect(Bool(false), "Expected blockMeta") }
    }
}
