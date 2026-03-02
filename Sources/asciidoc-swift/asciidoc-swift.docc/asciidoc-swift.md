# asciidoc-swift

A command-line interface for processing AsciiDoc files.

## Overview

The `asciidoc-swift` executable provides a CLI to convert, lint, and process AsciiDoc documents.

## Usage

```bash
asciidoc-swift <subcommand> [options]
```

### Subcommands

#### `json-adapter` subcommand

The json-adapter subcommand runs the JSON adapter.
The purpose of this is to convert AsciiDoc to the ASG JSON format
from the AsciiDoc TCK.

##### Usage

```bash
asciidoc-swift json-adapter [--stdin] [--plain] [--attribute <attribute> ...]
```

##### Arguments and Options

| Option | Description |
| :--- | :--- |
| `[<input-path>]` | Path to the input file (optional if `--stdin` is used) (default: `Last Argument`). |
| `--stdin` | Read AdapterInput JSON from stdin. |
| `--plain` | Treat input as plain AsciiDoc instead of JSON. |
| `-a`, `--attribute <attribute>` | Set document attribute (`name[=value]`). Repeatable. |
| `-h`, `--help` | Show help information. |

#### `html` subcommand

The html subcommand converts an AsciiDoc document to HTML5.

##### Usage

```bash
asciidoc-swift html [--stdin] [--template <template>] [--attribute <attribute> ...] [--output <output>] [<input-path>] [--extension <extension> ...]
```

##### Arguments and Options

| Option | Description |
| :--- | :--- |
| `<input-path>` | Path to the `.adoc` document (omit when using `--stdin`). |
| `--stdin` | Read source from stdin. Otherwise provide a path argument. |
| `--template <template>` | Path to the Stencil templates root directory. (default: `Templates`) |
| `--xad` | Enable XAD mode. |
| `--xad-strict` | Enable strict XAD parsing. |
| `--xad-paged-js` | Enable Paged.js hooks (HTML only). |
| `--xad-template <xad-template>` | Path to XAD template (`.adoc`). |
| `-a`, `--attribute <attribute>` | Set document attribute (`name[=value]`). Repeatable. |
| `-o`, `--output <output>` | Write rendered output to this path. |
| `-e`, `--extension <extension>` | Enable an extension by name (repeatable). |
| `-h`, `--help` | Show help information. |

#### `xad-html` subcommand

The xad-html subcommand converts an AsciiDoc document to HTML5 with XAD enabled.

##### Usage

```bash
asciidoc-swift xad-html [--stdin] [--template <template>] [--attribute <attribute> ...] [--output <output>] [<input-path>] [--extension <extension> ...]
```

##### Arguments and Options

| Option | Description |
| :--- | :--- |
| `<input-path>` | Path to the `.adoc` document (omit when using `--stdin`). |
| `--stdin` | Read source from stdin. Otherwise provide a path argument. |
| `--template <template>` | Path to the Stencil templates root directory. (default: `Templates`) |
| `--xad-strict` | Enable strict XAD parsing. |
| `--xad-template <xad-template>` | Path to XAD template (`.adoc`). |
| `-a`, `--attribute <attribute>` | Set document attribute (`name[=value]`). Repeatable. |
| `-o`, `--output <output>` | Write rendered output to this path. |
| `-e`, `--extension <extension>` | Enable an extension by name (repeatable). |
| `-h`, `--help` | Show help information. |

#### `xad-paged-html` subcommand

The xad-paged-html subcommand converts an AsciiDoc document to HTML5 with XAD enabled
and Paged.js hooks turned on.

##### Usage

```bash
asciidoc-swift xad-paged-html [--stdin] [--template <template>] [--xad-layout-template <layout>] [--xad-template-base <dir>] [--xad-template-search-path <dir> ...] [--list-xad-templates] [--attribute <attribute> ...] [--output <output>] [<input-path>] [--extension <extension> ...]
```

##### Arguments and Options

| Option | Description |
| :--- | :--- |
| `<input-path>` | Path to the `.adoc` document (omit when using `--stdin`). |
| `--stdin` | Read source from stdin. Otherwise provide a path argument. |
| `--template <template>` | Path to the Stencil templates root directory. (default: `Templates`) |
| `--xad-strict` | Enable strict XAD parsing. |
| `--xad-template <xad-template>` | Path to XAD template (`.adoc`). |
| `--xad-layout-template <layout>` | XAD paged layout template name or path (default: `default`). |
| `--xad-template-base <dir>` | Base directory for resolving XAD paged template paths. |
| `--xad-template-search-path <dir>` | Additional XAD paged template search paths (repeatable). |
| `--list-xad-templates` | List available XAD paged templates and exit. |
| `-a`, `--attribute <attribute>` | Set document attribute (`name[=value]`). Repeatable. |
| `-o`, `--output <output>` | Write rendered output to this path. |
| `-e`, `--extension <extension>` | Enable an extension by name (repeatable). |
| `-h`, `--help` | Show help information. |

##### XAD Layout Context

When using `xad-paged-html`, the parsed layout DSL is exposed in the render context under `xad.layoutProgram`. The structure is JSON-friendly and includes `expressions` with `node` and `value` entries (each node includes `name`, `args`, and `children`).


#### `docbook` subcommand

The docbook subcommand converts an AsciiDoc document to DocBook 5 XML.
DocBook can be converded to PDF using XSLT and FOP,
or to HTML using `saxon` and `docbook-xslTNG`.

##### Usage

```bash
asciidoc-swift docbook [--stdin] [--template <template>] [--attribute <attribute> ...] [--output <output>] [<input-path>] [--extension <extension> ...]
```

##### Arguments and Options

| Option | Description |
| :--- | :--- |
| `<input-path>` | Path to the `.adoc` document (omit when using `--stdin`). |
| `--stdin` | Read source from stdin. Otherwise provide a path argument. |
| `--template <template>` | Path to the Stencil templates root directory. (default: `Templates`) |
| `--xad` | Enable XAD mode. |
| `--xad-strict` | Enable strict XAD parsing. |
| `--xad-paged-js` | Enable Paged.js hooks (HTML only). |
| `--xad-template <xad-template>` | Path to XAD template (`.adoc`). |
| `-a`, `--attribute <attribute>` | Set document attribute (`name[=value]`). Repeatable. |
| `-o`, `--output <output>` | Write rendered output to this path. |
| `-e`, `--extension <extension>` | Enable an extension by name (repeatable). |
| `-h`, `--help` | Show help information. |

#### `latex` subcommand

The latex subcommand converts an AsciiDoc document to LaTeX.
If an SVG image is included, the image will be handled by the `svg`-package.
The SVG package converts SVG to PNG using `inkscape`,
which is a requirement for building such LaTeX documents.

##### Usage

```bash
asciidoc-swift latex [--stdin] [--template <template>] [--attribute <attribute> ...] [--output <output>] [<input-path>] [--extension <extension> ...]
```

##### Arguments and Options

| Option | Description |
| :--- | :--- |
| `<input-path>` | Path to the `.adoc` document (omit when using `--stdin`). |
| `--stdin` | Read source from stdin. Otherwise provide a path argument. |
| `--template <template>` | Path to the Stencil templates root directory. (default: `Templates`) |
| `--xad` | Enable XAD mode. |
| `--xad-strict` | Enable strict XAD parsing. |
| `--xad-paged-js` | Enable Paged.js hooks (HTML only). |
| `--xad-template <xad-template>` | Path to XAD template (`.adoc`). |
| `-a`, `--attribute <attribute>` | Set document attribute (`name[=value]`). Repeatable. |
| `-o`, `--output <output>` | Write rendered output to this path. |
| `-e`, `--extension <extension>` | Enable an extension by name (repeatable). |
| `-h`, `--help` | Show help information. |


#### `lint` subcommand

The lint subcommand checks an AsciiDoc document for style and semantic issues.
It currently supports spell checking and semantic break checks.

##### Usage

```bash
asciidoc-swift lint [--stdin] [--no-spellcheck] [--no-semantic-breaks] [--spell-lang <spell-lang>] [<input-path>]
```

##### Arguments and Options

| Option | Description |
| :--- | :--- |
| `<input-path>` | Path to the `.adoc` document. |
| `--stdin` | Read source from stdin. Otherwise provide a path argument. |
| `--no-spellcheck` | Disable spell checking. |
| `--no-semantic-breaks` | Disable semantic break checks. |
| `--spell-lang <spell-lang>` | Language passed to the aspell spellchecker (default: `en_US`). |
| `-h`, `--help` | Show help information. |



## Topics
 
### Modules

- [AsciiDocCore](../asciidoccore)
- [AsciiDocRender](../asciidocrender)
- [AsciiDocPagedRendering](../asciidocpagedrendering)
- [AsciiDocTools](../asciidoctools)
- [AsciiDocExtensions](../asciidocextensions)

