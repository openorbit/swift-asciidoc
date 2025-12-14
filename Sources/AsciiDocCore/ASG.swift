//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

import Foundation

public enum ASGConstDocumentName: String, Codable { case document }
public enum ASGConstBlockType: String, Codable { case block }
public enum ASGConstInlineType: String, Codable { case inline }
public enum ASGConstStringType: String, Codable { case string }

public struct ASGLocationBoundary: Codable, Equatable {
    public var line: Int
    public var col: Int
    public var file: [String]?

    public init(line: Int, col: Int, file: [String]? = nil) {
        self.line = line
        self.col = col
        self.file = file
    }
}

public struct ASGLocation: Codable, Equatable {
    public var start: ASGLocationBoundary
    public var end: ASGLocationBoundary

    public init(start: ASGLocationBoundary, end: ASGLocationBoundary) {
        self.start = start
        self.end = end
    }

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let start = try container.decode(ASGLocationBoundary.self)
        let end   = try container.decode(ASGLocationBoundary.self)
        self.start = start
        self.end = end
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(start)
        try container.encode(end)
    }
}

public struct ASGAuthor: Codable, Equatable {
    public var fullname: String?
    public var initials: String?
    public var firstname: String?
    public var middlename: String?
    public var lastname: String?
    public var address: String?

    public init(
        fullname: String? = nil,
        initials: String? = nil,
        firstname: String? = nil,
        middlename: String? = nil,
        lastname: String? = nil,
        address: String? = nil
    ) {
        self.fullname = fullname
        self.initials = initials
        self.firstname = firstname
        self.middlename = middlename
        self.lastname = lastname
        self.address = address
    }
}

// Forward declarations
public enum ASGInline: Codable, Equatable {
  case span(ASGInlineSpan)
  case ref(ASGInlineRef)
  case literal(ASGInlineLiteral)
}
public typealias ASGInlines = [ASGInline]

// Title/authors/location container in header
public struct ASGHeader: Codable, Equatable {
    public var title: ASGInlines?
    public var authors: [ASGAuthor]?
    public var location: ASGLocation?

    public init(title: ASGInlines? = nil, authors: [ASGAuthor]? = nil, location: ASGLocation? = nil) {
        self.title = title
        self.authors = authors
        self.location = location
    }
}

public struct ASGBlockMetadata: Codable, Equatable {
    public var attributes: [String: String]?       // pattern-constrained by schema; here as plain dict
    public var options: [String]?
    public var roles: [String]?
    public var location: ASGLocation?

    public init(
        attributes: [String: String]? = nil,
        options: [String]? = nil,
        roles: [String]? = nil,
        location: ASGLocation? = nil
    ) {
        self.attributes = attributes
        self.options = options
        self.roles = roles
        self.location = location
    }
}

public enum ASGInlineSpanVariant: String, Codable { case strong, emphasis, code, mark }
public enum ASGInlineSpanForm: String, Codable { case constrained, unconstrained }

public struct ASGAbstractParentInline: Codable, Equatable {
    public var type: ASGConstInlineType
    public var inlines: ASGInlines
    public var location: ASGLocation?

    public init(type: ASGConstInlineType = .inline, inlines: ASGInlines, location: ASGLocation? = nil) {
        self.type = type
        self.inlines = inlines
        self.location = location
    }
}

public struct ASGInlineSpan: Codable, Equatable {
    public var name: String // "span"
    public var type: ASGConstInlineType
    public var inlines: ASGInlines
    public var location: ASGLocation?
    public var variant: ASGInlineSpanVariant
    public var form: ASGInlineSpanForm

    public init(variant: ASGInlineSpanVariant, form: ASGInlineSpanForm, inlines: ASGInlines, location: ASGLocation? = nil) {
        self.name = "span"
        self.type = .inline
        self.variant = variant
        self.form = form
        self.inlines = inlines
        self.location = location
    }
}

public enum ASGInlineRefVariant: String, Codable { case link, xref }

public struct ASGInlineRef: Codable, Equatable {
    public var name: String // "ref"
    public var type: ASGConstInlineType
    public var inlines: ASGInlines
    public var location: ASGLocation?
    public var variant: ASGInlineRefVariant
    public var target: String

    public init(variant: ASGInlineRefVariant, target: String, inlines: ASGInlines, location: ASGLocation? = nil) {
        self.name = "ref"
        self.type = .inline
        self.variant = variant
        self.target = target
        self.inlines = inlines
        self.location = location
    }
}

public enum ASGInlineLiteralName: String, Codable { case text, charref, raw }

public struct ASGInlineLiteral: Codable, Equatable {
    public var name: ASGInlineLiteralName
    public var type: ASGConstStringType
    public var value: String
    public var location: ASGLocation?

    public init(name: ASGInlineLiteralName, value: String, location: ASGLocation? = nil) {
        self.name = name
        self.type = .string
        self.value = value
        self.location = location
    }
}

// Custom Inline discriminator
extension ASGInline {
    private enum CodingKeys: String, CodingKey { case name }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let name = try c.decode(String.self, forKey: .name)
        switch name {
        case "span":
            self = .span(try ASGInlineSpan(from: decoder))
        case "ref":
            self = .ref(try ASGInlineRef(from: decoder))
        case "text", "charref", "raw":
            self = .literal(try ASGInlineLiteral(from: decoder))
        default:
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown inline name: \(name)"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .span(let v): try v.encode(to: encoder)
        case .ref(let v): try v.encode(to: encoder)
        case .literal(let v): try v.encode(to: encoder)
        }
    }
}

// Common enumerations
public enum ASGListVariant: String, Codable { case callout, ordered, unordered }
public enum ASGBreakVariant: String, Codable { case page, thematic }
public enum ASGBlockMacroName: String, Codable { case audio, video, image, toc }
public enum ASGLeafBlockName: String, Codable { case listing, literal, paragraph, pass, stem, verse }
public enum ASGLeafBlockForm: String, Codable { case delimited, indented, paragraph }
public enum ASGParentBlockName: String, Codable { case admonition, example, sidebar, open, quote }
public enum ASGParentBlockVariant: String, Codable { case caution, important, note, tip, warning }

// Abstract block fields (flattened in each concrete block/section)
public protocol ASGHasAbstractBlock {
    var type: ASGConstBlockType { get set }
    var id: String? { get set }
    var title: ASGInlines? { get set }
    var reftext: ASGInlines? { get set }
    var metadata: ASGBlockMetadata? { get set }
    var location: ASGLocation? { get set }
}

// Abstract heading fields
public protocol ASGHasAbstractHeading: ASGHasAbstractBlock {
    var level: Int { get set }
}

// List item shared
public protocol ASGHasAbstractListItem: ASGHasAbstractBlock {
    var marker: String { get set }
    var principal: ASGInlines? { get set }
    var blocks: ASGNonSectionBlockBody? { get set }
}

// Section
public struct ASGSection: Codable, Equatable, ASGHasAbstractHeading {
    public var type: ASGConstBlockType
    public var id: String?
    public var title: ASGInlines?
    public var reftext: ASGInlines?
    public var metadata: ASGBlockMetadata?
    public var location: ASGLocation?

    public var level: Int
    public var name: String // "section"
    public var blocks: ASGSectionBody

    public init(level: Int, title: ASGInlines, blocks: ASGSectionBody = [], id: String? = nil, reftext: ASGInlines? = nil, metadata: ASGBlockMetadata? = nil, location: ASGLocation? = nil) {
        self.type = .block
        self.id = id
        self.title = title
        self.reftext = reftext
        self.metadata = metadata
        self.location = location
        self.level = level
        self.name = "section"
        self.blocks = blocks
    }
}

// List
public struct ASGList: Codable, Equatable, ASGHasAbstractBlock {
    public var type: ASGConstBlockType
    public var id: String?
    public var title: ASGInlines?
    public var reftext: ASGInlines?
    public var metadata: ASGBlockMetadata?
    public var location: ASGLocation?

    public var name: String // "list"
    public var marker: String
    public var variant: ASGListVariant
    public var items: [ASGListItem]

    public init(marker: String, variant: ASGListVariant, items: [ASGListItem], id: String? = nil, title: ASGInlines? = nil, reftext: ASGInlines? = nil, metadata: ASGBlockMetadata? = nil, location: ASGLocation? = nil) {
        self.type = .block
        self.id = id
        self.title = title
        self.reftext = reftext
        self.metadata = metadata
        self.location = location
        self.name = "list"
        self.marker = marker
        self.variant = variant
        self.items = items
    }
}

// DList
public struct ASGDList: Codable, Equatable, ASGHasAbstractBlock {
    public var type: ASGConstBlockType
    public var id: String?
    public var title: ASGInlines?
    public var reftext: ASGInlines?
    public var metadata: ASGBlockMetadata?
    public var location: ASGLocation?

    public var name: String // "dlist"
    public var marker: String
    public var items: [ASGDListItem]

    public init(type: ASGConstBlockType = .block,
                id: String? = nil,
                title: ASGInlines? = nil,
                reftext: ASGInlines? = nil,
                metadata: ASGBlockMetadata? = nil,
                location: ASGLocation? = nil,
                name: String = "dlist",
                marker: String,
                items: [ASGDListItem]) {
        self.type = type
        self.id = id
        self.title = title
        self.reftext = reftext
        self.metadata = metadata
        self.location = location
        self.name = name
        self.marker = marker
        self.items = items
    }
}

// ListItem
public struct ASGListItem: Codable, Equatable, ASGHasAbstractListItem {
    public var type: ASGConstBlockType
    public var id: String?
    public var title: ASGInlines?
    public var reftext: ASGInlines?
    public var metadata: ASGBlockMetadata?
    public var location: ASGLocation?

    public var name: String // "listItem"
    public var marker: String
    public var principal: ASGInlines?
    public var blocks: ASGNonSectionBlockBody?

    public init(marker: String, principal: ASGInlines, blocks: ASGNonSectionBlockBody? = nil, id: String? = nil, title: ASGInlines? = nil, reftext: ASGInlines? = nil, metadata: ASGBlockMetadata? = nil, location: ASGLocation? = nil) {
        self.type = .block
        self.id = id
        self.title = title
        self.reftext = reftext
        self.metadata = metadata
        self.location = location
        self.name = "listItem"
        self.marker = marker
        self.principal = principal
        self.blocks = blocks
    }
}

// DListItem
public struct ASGDListItem: Codable, Equatable, ASGHasAbstractListItem {
    public var type: ASGConstBlockType
    public var id: String?
    public var title: ASGInlines?
    public var reftext: ASGInlines?
    public var metadata: ASGBlockMetadata?
    public var location: ASGLocation?

    public var name: String // "dlistItem"
    public var marker: String
    public var principal: ASGInlines?
    public var blocks: ASGNonSectionBlockBody?
    public var terms: [ASGInlines]

    public init(type: ASGConstBlockType = .block,
                id: String? = nil,
                title: ASGInlines? = nil,
                reftext: ASGInlines? = nil,
                metadata: ASGBlockMetadata? = nil,
                location: ASGLocation? = nil,
                name: String = "dlistItem",
                marker: String,
                principal: ASGInlines? = nil,
                blocks: ASGNonSectionBlockBody? = nil,
                terms: [ASGInlines]) {
        self.type = .block
        self.id = id
        self.title = title
        self.reftext = reftext
        self.metadata = metadata
        self.location = location
        self.name = "dlistItem"
        self.marker = marker
        self.terms = terms
        self.principal = principal
        self.blocks = blocks
    }
}

// Discrete heading ("heading")
public struct ASGDiscreteHeading: Codable, Equatable, ASGHasAbstractHeading {
    public var type: ASGConstBlockType
    public var id: String?
    public var title: ASGInlines?
    public var reftext: ASGInlines?
    public var metadata: ASGBlockMetadata?
    public var location: ASGLocation?

    public var level: Int
    public var name: String // "heading"

    public init(level: Int, title: ASGInlines, id: String? = nil, reftext: ASGInlines? = nil, metadata: ASGBlockMetadata? = nil, location: ASGLocation? = nil) {
        self.type = .block
        self.id = id
        self.title = title
        self.reftext = reftext
        self.metadata = metadata
        self.location = location
        self.level = level
        self.name = "heading"
    }
}

// Break
public struct ASGBreak: Codable, Equatable, ASGHasAbstractBlock {
    public var type: ASGConstBlockType
    public var id: String?
    public var title: ASGInlines?
    public var reftext: ASGInlines?
    public var metadata: ASGBlockMetadata?
    public var location: ASGLocation?

    public var name: String // "break"
    public var variant: ASGBreakVariant

    public init(variant: ASGBreakVariant, id: String? = nil, title: ASGInlines? = nil, reftext: ASGInlines? = nil, metadata: ASGBlockMetadata? = nil, location: ASGLocation? = nil) {
        self.type = .block
        self.id = id
        self.title = title
        self.reftext = reftext
        self.metadata = metadata
        self.location = location
        self.name = "break"
        self.variant = variant
    }
}

// Block macro
public struct ASGBlockMacro: Codable, Equatable, ASGHasAbstractBlock {
    public var type: ASGConstBlockType
    public var id: String?
    public var title: ASGInlines?
    public var reftext: ASGInlines?
    public var metadata: ASGBlockMetadata?
    public var location: ASGLocation?

    public var name: ASGBlockMacroName
    public var form: String // "macro"
    public var target: String?

    public init(name: ASGBlockMacroName, target: String? = nil, id: String? = nil, title: ASGInlines? = nil, reftext: ASGInlines? = nil, metadata: ASGBlockMetadata? = nil, location: ASGLocation? = nil) {
        self.type = .block
        self.id = id
        self.title = title
        self.reftext = reftext
        self.metadata = metadata
        self.location = location
        self.name = name
        self.form = "macro"
        self.target = target
    }
}

// Leaf block
public struct ASGLeafBlock: Codable, Equatable, ASGHasAbstractBlock {
    public var type: ASGConstBlockType
    public var id: String?
    public var title: ASGInlines?
    public var reftext: ASGInlines?
    public var metadata: ASGBlockMetadata?
    public var location: ASGLocation?

    public var name: ASGLeafBlockName
    public var form: ASGLeafBlockForm?
    public var delimiter: String?
    public var inlines: ASGInlines?

    public init(name: ASGLeafBlockName, form: ASGLeafBlockForm? = nil, delimiter: String? = nil, inlines: ASGInlines? = [], id: String? = nil, title: ASGInlines? = nil, reftext: ASGInlines? = nil, metadata: ASGBlockMetadata? = nil, location: ASGLocation? = nil) {
        self.type = .block
        self.id = id
        self.title = title
        self.reftext = reftext
        self.metadata = metadata
        self.location = location
        self.name = name
        self.form = form
        self.delimiter = delimiter
        self.inlines = inlines
    }
}

// Parent block
public struct ASGParentBlock: Codable, Equatable, ASGHasAbstractBlock {
    public var type: ASGConstBlockType
    public var id: String?
    public var title: ASGInlines?
    public var reftext: ASGInlines?
    public var metadata: ASGBlockMetadata?
    public var location: ASGLocation?

    public var name: ASGParentBlockName
    public var form: String // "delimited"
    public var delimiter: String
    public var variant: ASGParentBlockVariant?
    public var blocks: ASGNonSectionBlockBody

    public init(type: ASGConstBlockType = .block,
                name: ASGParentBlockName,
                form: String = "delimited",
                delimiter: String,
                blocks: ASGNonSectionBlockBody = [],
                variant: ASGParentBlockVariant? = nil,
                id: String? = nil,
                title: ASGInlines? = nil,
                reftext: ASGInlines? = nil,
                metadata: ASGBlockMetadata? = nil,
                location: ASGLocation? = nil) {
        self.type = type
        self.id = id
        self.title = title
        self.reftext = reftext
        self.metadata = metadata
        self.location = location
        self.name = name
        self.form = form
        self.delimiter = delimiter
        self.variant = variant
        self.blocks = blocks
    }
}

public enum ASGBlock: Codable, Equatable {
    case list(ASGList)
    case dlist(ASGDList)
    case discreteHeading(ASGDiscreteHeading) // name == "heading"
    case `break`(ASGBreak)
    case blockMacro(ASGBlockMacro)
    case leaf(ASGLeafBlock)
    case parent(ASGParentBlock)

    private enum CodingKeys: String, CodingKey { case name }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let name = try c.decode(String.self, forKey: .name)
        switch name {
        case "list": self = .list(try ASGList(from: decoder))
        case "dlist": self = .dlist(try ASGDList(from: decoder))
        case "heading": self = .discreteHeading(try ASGDiscreteHeading(from: decoder))
        case "break": self = .break(try ASGBreak(from: decoder))
        case "audio", "video", "image", "toc": self = .blockMacro(try ASGBlockMacro(from: decoder))
        case "listing", "literal", "paragraph", "pass", "stem", "verse": self = .leaf(try ASGLeafBlock(from: decoder))
        case "admonition", "example", "sidebar", "open", "quote": self = .parent(try ASGParentBlock(from: decoder))
        default:
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown block name: \(name)"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .list(let v): try v.encode(to: encoder)
        case .dlist(let v): try v.encode(to: encoder)
        case .discreteHeading(let v): try v.encode(to: encoder)
        case .break(let v): try v.encode(to: encoder)
        case .blockMacro(let v): try v.encode(to: encoder)
        case .leaf(let v): try v.encode(to: encoder)
        case .parent(let v): try v.encode(to: encoder)
        }
    }
}

public typealias ASGNonSectionBlockBody = [ASGBlock]

// Section body = [block | section]
public enum ASGSectionBodyItem: Codable, Equatable {
    case block(ASGBlock)
    case section(ASGSection)

    private enum Discriminator: String, CodingKey { case name }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Discriminator.self)
        if let name = try c.decodeIfPresent(String.self, forKey: .name), name == "section" {
            self = .section(try ASGSection(from: decoder))
        } else {
            self = .block(try ASGBlock(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .block(let b): try b.encode(to: encoder)
        case .section(let s): try s.encode(to: encoder)
        }
    }
}

public typealias ASGSectionBody = [ASGSectionBodyItem]

public struct ASGDocument: Codable, Equatable {
    public var name: ASGConstDocumentName
    public var type: ASGConstBlockType
    /// PatternProperties: keys match ^[a-zA-Z0-9_][-a-zA-Z0-9_]*$, values string or null
    public var attributes: [String: String]?
    public var header: ASGHeader?
    public var blocks: ASGSectionBody?
    public var location: ASGLocation?

    public init(
        attributes: [String: String?]? = nil,
        header: ASGHeader? = nil,
        blocks: ASGSectionBody = [],
        location: ASGLocation? = nil
    ) {
        self.name = .document
        self.type = .block
        if header != nil {
            if let attributes {
                self.attributes = attributes.mapValues { $0 ?? "" }
            } else {
                self.attributes = nil
            }
        } else {
            if let attributes {
                self.attributes = attributes.count > 0 ? attributes.mapValues { $0 ?? "" } : nil
            } else {
                self.attributes = nil
            }
        }
        self.header = header
        self.blocks = blocks.count > 0 ? blocks : nil
        self.location = location
    }
}

// Optional: Call these after decoding (or before encoding) to enforce schema constraints.
public enum ASGValidationError: Error, CustomStringConvertible {
    case documentHeaderRequiresAttributes
    case leafBlockDelimiterMissingWhenDelimited
    case parentBlockVariantRequiredForAdmonition
    case sectionTitleOrLevelMissing
    case inlineParentMissingInlines

    public var description: String {
        switch self {
        case .documentHeaderRequiresAttributes: return "Document has 'header' but missing 'attributes'."
        case .leafBlockDelimiterMissingWhenDelimited: return "Leaf block with form 'delimited' requires 'delimiter'."
        case .parentBlockVariantRequiredForAdmonition: return "Parent block 'admonition' requires 'variant'."
        case .sectionTitleOrLevelMissing: return "Sections/headings must include title and non-negative level."
        case .inlineParentMissingInlines: return "Abstract parent inline requires 'inlines'."
        }
    }
}

public extension ASGDocument {
    func validate() throws {
        if header != nil && attributes == nil {
            throw ASGValidationError.documentHeaderRequiresAttributes
        }
        try blocks?.forEach { try $0.validateRec() }
    }
}

private extension ASGSectionBodyItem {
    func validateRec() throws {
        switch self {
        case .section(let s):
            guard s.title != nil, s.level >= 0 else { throw ASGValidationError.sectionTitleOrLevelMissing }
            try s.blocks.forEach { try $0.validateRec() }
        case .block(let b):
            try b.validate()
        }
    }
}

private extension ASGBlock {
    func validate() throws {
        switch self {
        case .leaf(let lb):
            if lb.form == .delimited && (lb.delimiter == nil || lb.delimiter?.isEmpty == true) {
                throw ASGValidationError.leafBlockDelimiterMissingWhenDelimited
            }
        case .parent(let pb):
            if pb.name == .admonition && pb.variant == nil {
                throw ASGValidationError.parentBlockVariantRequiredForAdmonition
            }
        case .list, .dlist, .discreteHeading, .break, .blockMacro:
            break
        }
    }
}
