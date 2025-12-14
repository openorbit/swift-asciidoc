# asciidoc-swift

A command-line interface for processing AsciiDoc files.

## Overview

The `asciidoc-swift` executable provides a CLI to convert, lint, and process AsciiDoc documents.

## Usage

```bash
asciidoc-swift <subcommand> [options]
```

## Topics
 
### Modules

- <doc:AsciiDocCore>
- <doc:AsciiDocRender>
- <doc:AsciiDocTools>
- <doc:AsciiDocExtensions>

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
| `-a`, `--attribute <attribute>` | Set document attribute (`name[=value]`). Repeatable. |
| `-o`, `--output <output>` | Write rendered output to this path. |
| `-e`, `--extension <extension>` | Enable an extension by name (repeatable). |
| `-h`, `--help` | Show help information. |


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
