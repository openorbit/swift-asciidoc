# AsciiDoc Block Editor Draft Specification

> **Superseded.** The per-block editor direction in this draft has been
> replaced by the AsciiDoc-native continuous semantic editor specified in
> [AsciiDoc Semantic Editor Architecture](AsciiDoc_Semantic_Editor_Architecture.md).
> This file remains as historical design context only.

## Status

Draft, intended to guide the first interactive iterations of the SwiftUI block editor.

## Purpose

Define a WYSIWYM editor for AsciiDoc that:

- uses the ISM (`AdocDocument`) as the primary editing model
- preserves structural meaning instead of emulating a line editor
- feels closer to a text editor than a collection of oversized cards or inspector panes
- makes a rendered preview optional rather than required

## Core Principles

### 1. ISM is the source of truth

The editor operates on `AdocDocument`, `AdocBlock`, `AdocText`, and related ISM nodes directly.

The editor must not depend on:

- ASG as its primary editing model
- an intermediate UI-only document representation as the canonical state
- export and reparse cycles to perform normal edits

Derived view models are allowed for presentation, but they must be transient and reversible to the underlying ISM node they represent.

### 2. WYSIWYM over WYSIWYG

The user edits document meaning and structure, not final rendering.

Examples:

- a section is edited as a section with a heading level, not as raw `==`
- a list item is edited as a list item, not as a line beginning with `*`
- an equation is edited as a math block with body and mode, not as a delimited text blob

The editor should show semantic cues directly in the editing surface so a preview is not needed for routine authoring.

### 2a. Semantic presentation mapping

Each supported AsciiDoc or ISM construct should have a native editable visual representation.

The editor should not default to showing source markers when a clearer semantic presentation is possible.

Representative mappings:

- `Section` / `== Heading`:
  large type, visually weighted, with heading semantics shown directly
- `[source,swift]` listing block:
  monospaced editing surface, syntax-highlighted when available, compact language badge
- `NOTE:` or admonition block:
  subtle colored left rule, icon, and type label
- `include::file[]`:
  inline or block chip/token, not directly text-editable in the main flow, but inspectable
- `*strong*`:
  rendered bold with source markers hidden in normal editing presentation
- `_emphasis_`:
  rendered italic with source markers hidden in normal editing presentation

Additional mappings should follow the same rule:

- preserve semantic meaning
- present the construct in the way authors think about it
- keep source syntax secondary unless the user explicitly enters a source-oriented fallback mode

### 3. Text-editor feel

The editor should visually read as one flowing document.

The UI should avoid:

- large card containers around every block
- excessive padding between blocks
- strong panel/chrome boundaries that fragment the page
- layouts that resemble form builders more than writing tools

The UI should prefer:

- a continuous vertical text flow
- subtle block affordances only when focused or hovered
- inline controls or gutter controls instead of persistent big tool panels
- typography and spacing that resemble a document editor

## Editing Model

### Editing foundation

The preferred foundation for text-bearing editing regions is TextKit 2.

This applies in particular to:

- document title editing
- section and heading text
- paragraphs
- list item principal text
- description list terms and definitions
- listing and literal text regions
- quote/admonition/example/sidebar/open block body text where those bodies are fundamentally textual

TextKit 2 is preferred because it better matches the target interaction model:

- a flowing text-editor-like surface
- native selection, caret, navigation, and editing behavior
- fine-grained layout control
- the ability to introduce custom layout fragments and content elements for semantic regions

Relevant architectural roles:

- `NSTextContentManager` or `NSTextContentStorage` should back the editable text content presented to the platform text system
- `NSTextLayoutManager` should own layout and selection behavior for text-bearing regions
- custom `NSTextLayoutFragment` or related adapter layers may be used to give semantic blocks lightweight visual treatment without turning the UI into large cards

SwiftUI may remain the outer application shell, but it should host TextKit 2 based editing surfaces where rich text-like behavior is required.

One useful way to think about this is as an ISM-to-text-system projection:

```text
ISM
 └── Section "Introduction"         → NSTextParagraph (heading style, e.g. h2)
 └── Paragraph "Some text..."       → NSTextParagraph (body style)
 └── ListingBlock [source,swift]    → NSTextParagraph (code style)
     └── attributed content with syntax highlighting
```

This projection should be semantic rather than source-syntactic.

That means:

- the text system should receive block role and presentation intent
- heading/list/code/admonition semantics should drive paragraph styling and layout behavior
- source markers like `==` or `[source,swift]` should not be the primary visible editing representation in normal mode

### Hybrid editing surface

The overall editor is expected to be hybrid rather than purely text-system-driven.

TextKit 2 is likely the right base for many block types, but not all of them.

Blocks should fall into these broad categories:

- text-native blocks, which should use TextKit 2 as the primary editing surface
- structured widget blocks, which may need specialized controls instead of a pure text system
- fallback blocks, which may need a preserved read-only or source-island representation

Examples of likely text-native blocks:

- paragraphs
- headings
- list items
- description list entries
- admonition bodies
- quote bodies
- listing text

Examples of likely specialized blocks:

- tables
- some equation editing modes
- custom block macros with app-specific controls

Tables in particular should not drive the architecture for the entire editor.
They are an exception case and should be handled as embedded structured widgets within the broader document flow.

### Document flow

The main surface is a single scrollable document view.

Each block occupies a span in that flow and should appear as part of the document, not as an isolated widget.

The document should support:

- caret movement through editable text regions
- block selection
- insertion between blocks
- reordering of blocks
- structural transformations of the selected block

### Block chrome

Block chrome should be minimal by default.

Recommended baseline:

- a narrow left gutter for insertion handles, drag handles, and block-type indicators
- a focused-state outline or background tint that is subtle
- floating or contextual controls only when a block or text region is active

Persistent full-width bordered containers should be avoided except where the semantic form demands it, such as tables.

### Toolbar model

There should be a compact toolbar near the top, but it should behave as an editing aid rather than as the primary interaction model.

The toolbar should expose:

- inline emphasis
- strong
- code
- mark
- block insertion
- block transformation where valid (e.g. make a line a heading, convert heading levels, convert heading to paragraph, etc)

Over time it may expose:

- table operations
- equation insertion
- bibliography insertion
- custom macro insertion

### Block transformation controls

Block transformation is a core editing capability and should be directly accessible from the toolbar or another similarly lightweight contextual control surface.

These controls should allow the user to reinterpret the current block semantically without manually rewriting source syntax.

Important early transformations include:

- paragraph to section / heading
- section / heading to paragraph
- heading level changes
- paragraph to verse
- paragraph to source / listing block
- paragraph to literal block
- paragraph to admonition or quote where valid
- source / verse / literal back to paragraph when content permits
- unordered list to ordered list and the reverse

Transformations should be selection-aware:

- if the caret is inside a text-bearing block, the current block is the transform target
- if one or more whole blocks are selected, the transform applies to those blocks where valid

Transformations should be semantic AST operations, not text-rewrite macros.

## Block Presentation Rules

### Paragraphs

Paragraphs should look like editable prose.

They should not carry visible paragraph framing unless focused.

### Sections and headings

Sections should present as headings in the document flow.

Heading level should be editable without forcing raw syntax visibility.

The user may see a subtle level affordance in the gutter or a compact level picker on focus.

### Lists

Lists should read like real lists in the editor surface.

The user should see:

- bullets or numbers
- indentation for nesting
- text editing inline with each item

The user should not primarily edit list markers as raw text syntax.

### Description lists

Description lists should appear as term-definition pairs with compact alignment.

They should not appear as two unrelated form fields inside a large container.

### Tables

Tables may be more visibly structured than prose blocks, but they should still remain part of the document flow.

Initial table editing may support a constrained subset:

- plain cell text
- row insertion/removal
- column insertion/removal
- optional header row semantics

### Equations

Equations should appear as math-authoring regions.

The editor does not need a final rendered math preview to be valid WYSIWYM, but it should clearly indicate:

- this is math content
- inline or display semantics
- math flavor where relevant

### Admonitions and parent blocks

Admonitions, examples, sidebars, open blocks, and quotes should not default to giant boxed panels.

They should use a restrained visual treatment:

- a type label or icon
- a subtle left rule or gutter marker
- lightweight grouping of the contained content

## Inline Content

Inline editing should be done in text contexts backed by `AdocText`.

For the long-term implementation, inline editing should preferably be mediated through a TextKit 2 bridge that maps editor state to and from `AdocInline` and `AdocText`.

The editor must preserve semantic inline structure where possible, including:

- emphasis
- strong
- monospace/code
- mark
- links
- xrefs
- inline math
- inline macros

Initial implementations may use normalized textual application of marks if direct attributed editing of the inline tree is not yet practical, but the long-term design target is structured inline editing over ISM using a TextKit 2 backed editing surface.

## Editing Operations

User-visible editing behavior should map to explicit ISM mutations.

Representative mappings:

| User action | AST / ISM mutation |
| --- | --- |
| Type at end of paragraph | Append content to the existing paragraph node |
| Press Return at heading | Insert a new paragraph node after the section or heading node |
| Select text and press `Cmd-B` | Wrap selection in a `strong` inline node |
| Backspace at start of heading | Merge with previous node where valid, or demote heading level depending on context |
| Press `Tab` in a list item | Increase list nesting level for the current item |
| Select text and type `` ` `` | Convert selection to monospace / inline source semantics rather than inserting literal marker characters in normal semantic editing mode |
| Choose `Heading 2` in transform controls | Convert current paragraph or heading into a section/heading node with level 2 |
| Choose `Paragraph` in transform controls | Convert current heading, verse, listing, or similar text-bearing block into a paragraph node where content can be preserved |
| Choose `Source` in transform controls | Convert current text-bearing block into a listing/source block and preserve textual content |
| Choose `Verse` in transform controls | Convert current text-bearing block into a verse node and preserve textual content |

These rules should be treated as semantic editor commands, not text substitutions over raw AsciiDoc source.

### Operation design constraints

Editing commands should:

- mutate the ISM directly
- preserve semantic structure whenever possible
- fall back to localized source-oriented behavior only when semantic editing is not available

When a block transform would lose semantics, the editor should either:

- refuse the transform with a clear explanation
- preserve unsupported semantics in block metadata or a fallback representation
- require an explicit destructive confirmation

Editing commands should not require:

- reparsing the whole document after each keystroke
- exposing raw AsciiDoc delimiters as the main interaction model
- a rendered preview to understand the result

## Import and Export

### Import

Import parses source into `AdocDocument`.

If a construct is unsupported by the current editing UI, the editor should:

- preserve the underlying ISM node if possible
- expose a degraded but non-destructive representation
- clearly mark unsupported editing regions

### Export

Export serializes the edited `AdocDocument`.

Round-tripping goals:

- structural edits should not destroy supported semantics
- serialization may normalize formatting
- exact line preservation is not required
- semantic idempotence is required for supported constructs

## Unsupported and Partially Supported Constructs

The editor should distinguish between:

- editable supported blocks
- read-only preserved blocks
- blocks requiring fallback source editing

Fallback handling should be explicit and local, not a reason to drop the user into raw source for the entire document.

## Initial Scope

The first serious editor milestone should support:

- document title
- sections
- paragraphs
- unordered lists
- ordered lists
- description lists
- listings
- math blocks
- basic tables
- admonitions and closely related parent blocks

The first milestone should also support:

- insertion between blocks
- deletion
- basic reordering
- inline formatting commands in text-bearing blocks

## Out of Scope for First Milestone

- perfect source fidelity
- complete AsciiDoc coverage
- final-rendered preview as a primary workflow
- advanced collaborative editing
- all extension and macro UIs
- full bibliography workflows

## Open Questions

1. Should sections remain true `AdocSection` nodes in the root block array during editing, or should the UI temporarily flatten them into a visible linear outline while preserving section ownership?
2. What is the preferred fallback UI for unsupported blocks: embedded raw-source islands, read-only labeled blocks, or a mixed approach?
3. How should a TextKit 2 bridge map between platform attributed text state and `AdocInline` without losing unsupported inline semantics?
4. How much source normalization is acceptable when exporting edited tables and nested lists?
5. Which block types should explicitly remain outside the TextKit 2 surface from the start, rather than being forced through it?

## Immediate Consequences for Current Prototype

The current prototype should evolve in these directions:

- replace card-heavy block rendering with a flowing document layout
- move controls into a gutter and contextual overlays
- keep `AdocDocument` as the only canonical editing state
- remove preview-oriented UX from the main example app
- treat unsupported block types as explicit fallback regions instead of silently converting them
- treat TextKit 2 as the default editing substrate for text-bearing blocks, not as an optional enhancement
