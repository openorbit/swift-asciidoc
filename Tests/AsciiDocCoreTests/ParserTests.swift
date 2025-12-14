import Testing
import Foundation
@testable import AsciiDocCore   // replace with the module that exposes AdocParser, AdocDocument.toASG(), ASGDocument

private enum ASGInspector {
  static func plain(_ inlines: ASGInlines?) -> String {
    guard let xs = inlines else { return "" }
    func walk(_ n: ASGInline, _ out: inout String) {
      switch n {
      case .literal(let lit):
        out += lit.value
      case .span(let sp):
        sp.inlines.forEach { walk($0, &out) }
      case .ref(let r):
        r.inlines.forEach { walk($0, &out) }
      }
    }
    var s = ""
    xs.forEach { walk($0, &s) }
    return s
  }

  static func sections(_ doc: ASGDocument) -> [(level: Int, title: String)] {
    func walkBody(_ body: ASGSectionBody) -> [(Int, String)] {
      var acc: [(Int, String)] = []
      for item in body {
        switch item {
        case .section(let s):
          acc.append((s.level, plain(s.title)))
          acc.append(contentsOf: walkBody(s.blocks))
        case .block:
          break
        }
      }
      return acc
    }
    return walkBody(doc.blocks!)
  }

  static func paragraphs(_ doc: ASGDocument) -> [String] {
    func fromBlock(_ b: ASGBlock) -> [String] {
      switch b {
      case .leaf(let lb) where lb.name == .paragraph:
        return [plain(lb.inlines)]
      case .parent(let pb):
        return pb.blocks.flatMap(fromBlock)
      case .list(let l):
        return l.items.flatMap { item in
          (item.principal.map { [plain($0)] } ?? []) +
          (item.blocks?.flatMap(fromBlock) ?? [])
        }
      case .dlist(let dl):
        return dl.items.flatMap { $0.blocks?.flatMap(fromBlock) ?? [] }
      case .discreteHeading, .break, .blockMacro, .leaf, .list, .dlist:
        return []
      }
    }
    func walkBody(_ body: ASGSectionBody) -> [String] {
      var acc: [String] = []
      for item in body {
        switch item {
        case .block(let b): acc += fromBlock(b)
        case .section(let s):
          acc += walkBody(s.blocks)
        }
      }
      return acc
    }
    return walkBody(doc.blocks!)
  }

  static func lists(_ doc: ASGDocument) -> [(variant: ASGListVariant, count: Int)] {
    func fromBlock(_ b: ASGBlock) -> [(ASGListVariant, Int)] {
      switch b {
      case .list(let l): return [(l.variant, l.items.count)]
      case .parent(let pb): return pb.blocks.flatMap(fromBlock)
      case .leaf, .dlist, .discreteHeading, .break, .blockMacro: return []
      }
    }
    func walkBody(_ body: ASGSectionBody) -> [(ASGListVariant, Int)] {
      body.flatMap {
        switch $0 {
        case .block(let b): return fromBlock(b)
        case .section(let s): return walkBody(s.blocks)
        }
      }
    }
    return walkBody(doc.blocks!)
  }

  static func listings(_ doc: ASGDocument) -> [(delimiter: String?, text: String)] {
    func fromBlock(_ b: ASGBlock) -> [(String?, String)] {
      switch b {
      case .leaf(let lb) where lb.name == .listing:
        return [(lb.delimiter, plain(lb.inlines))]
      case .parent(let pb):
        return pb.blocks.flatMap(fromBlock)
      case .list(let l):
        return l.items.flatMap { $0.blocks?.flatMap(fromBlock) ?? [] }
      case .leaf, .dlist, .discreteHeading, .break, .blockMacro:
        return []
      }
    }
    func walkBody(_ body: ASGSectionBody) -> [(String?, String)] {
      body.flatMap {
        switch $0 {
        case .block(let b): return fromBlock(b)
        case .section(let s): return walkBody(s.blocks)
        }
      }
    }
    return walkBody(doc.blocks!)
  }
}

private func parseToASG(_ src: String) -> ASGDocument {
  let parser = AdocParser()
  let ism = parser.parse(text: src)
  return ism.toASG()
}

@Suite("Core parser")
struct ParserTests {

  @Suite("Attributes & headers")
  struct AttributeHandling {

    @Test
    func parser_respects_seed_attributes() {
      let parser = AdocParser()
      let doc = parser.parse(
        text: """
        Body only
        """,
        attributes: ["product": "CLI"]
      )
      #expect(doc.attributes["product"] == "CLI")
    }

    @Test
    func locked_attributes_prevent_header_override() {
      let src = """
      :product: Document value

      = Title
      """
      let parser = AdocParser()
      let doc = parser.parse(
        text: src,
        attributes: ["product": "CLI"],
        lockedAttributeNames: Set(["product"])
      )
      #expect(doc.attributes["product"] == "CLI")
    }

    @Test
    func header_sets_derived_attributes() {
      let src = """
      = Sample Guide
      Jane Doe <jane@example.com>
      v1.2, 2024-05-01: Draft

      Body text
      """

      let parser = AdocParser()
      let doc = parser.parse(text: src)

      #expect(doc.attributes["doctitle"] == "Sample Guide")
      #expect(doc.attributes["author"] == "Jane Doe")
      #expect(doc.attributes["authors"] == "Jane Doe")
      #expect(doc.attributes["firstname"] == "Jane")
      #expect(doc.attributes["lastname"] == "Doe")
      #expect(doc.attributes["email"] == "jane@example.com")
      #expect(doc.attributes["revnumber"] == "v1.2")
      #expect(doc.attributes["revdate"] == "2024-05-01")
      #expect(doc.attributes["revremark"] == "Draft")
    }

    @Test
    func derived_header_attributes_respect_locks() {
      let src = """
      = Locked Title
      John Q. Public

      Body
      """

      let parser = AdocParser()
      let doc = parser.parse(
        text: src,
        attributes: ["doctitle": "Override"],
        lockedAttributeNames: Set(["doctitle", "author"])
      )

      #expect(doc.attributes["doctitle"] == "Override")
      #expect(doc.attributes["author"] == nil)
    }
  }

  @Suite("ASG bridging")
  struct ASGExport {

    @Test
    func paragraph_to_asg() {
      let asg = parseToASG("Hello world\n\n")
      let paras = ASGInspector.paragraphs(asg)
      #expect(paras == ["Hello world"])
    }

    @Test
    func atx_sections_nesting() {
      let src = """
      = Title
      == Alpha
      Body A

      == Beta
      Body B
      """
      let asg = parseToASG(src)

      let secs = ASGInspector.sections(asg)

      // #expect(asg.header?.title. "Title")
      #expect(secs.contains(where: { $0.level == 1 && $0.title == "Alpha" }))
      #expect(secs.contains(where: { $0.level == 1 && $0.title == "Beta" }))

      let paras = ASGInspector.paragraphs(asg)
      #expect(paras.contains("Body A"))
      #expect(paras.contains("Body B"))
    }

    @Test
    func list_with_continuation() {
      let src = """
      * Item one
      +
      Continuation para

      * Item two
      """
      let asg = parseToASG(src)

      let ls = ASGInspector.lists(asg)
      #expect(ls.contains(where: { $0.variant == .unordered && $0.count == 2 }))

      // First item has a continuation paragraph somewhere under it
      let paras = ASGInspector.paragraphs(asg)
      #expect(paras.contains("Continuation para"))
    }

    @Test
    func listing_block_fenced() {
      let src = """
      ----
      line A
      line B
      ----
      """
      let asg = parseToASG(src)

      let lst = ASGInspector.listings(asg)
      #expect(lst.contains(where: { $0.delimiter == "----" && $0.text == "line A\nline B" }))
    }
  }

  @Suite("Integration scenarios")
  struct Integration {

    @Test
    func block_anchor_sets_reftext() {
      let src = """
      [[intro,Intro caption]]
      Intro paragraph
      """

      let parser = AdocParser()
      let doc = parser.parse(text: src)

      #expect(doc.blocks.count == 1)
      guard case .paragraph(let para) = doc.blocks.first else {
        Issue.record("Expected first block to be a paragraph")
        return
      }

      #expect(para.id == "intro")
      #expect(para.reftext?.plain == "Intro caption")
    }

    @Test
    func mixed_document_smoke() {
      let src = """
      = Doc
      Intro para

      == Section
      * One
      * Two
      ----
      Verbatim
      ----
      """
      let asg = parseToASG(src)

      let secs = ASGInspector.sections(asg)
      //#expect(secs.contains(where: { $0.level == 1 && $0.title == "Doc" }))
      #expect(secs.contains(where: { $0.level == 1 && $0.title == "Section" }))

      let paras = ASGInspector.paragraphs(asg)
      //#expect(paras.contains("Intro para"))

      let ls = ASGInspector.lists(asg)
      #expect(ls.contains(where: { $0.variant == .unordered && $0.count == 2 }))

      let listings = ASGInspector.listings(asg)
      #expect(listings.contains(where: { $0.text == "Verbatim" }))
    }

    @Test
    func callout_lists_parse_and_render() {
      let src = """
      [source]
      ----
      puts "hi" <1>
      ----

      <1> Print greeting
      <2> Return value
      """

      let parser = AdocParser()
      let doc = parser.parse(text: src)

      guard let lastBlock = doc.blocks.last else {
        Issue.record("expected a callout list block")
        return
      }

      guard case .list(let callouts) = lastBlock else {
        Issue.record("last block was not a list")
        return
      }

      #expect(callouts.kind == .callout)
      #expect(callouts.items.count == 2)
      #expect(callouts.items.first?.marker == "<1>")
      #expect(callouts.items.last?.marker == "<2>")

      let asg = doc.toASG()
      let variants = ASGInspector.lists(asg)
      #expect(variants.contains { $0.variant == .callout && $0.count == 2 })
    }
  }
}
