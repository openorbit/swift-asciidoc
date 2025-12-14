#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/compare-perf.sh <document.adoc>

Compare the runtime of asciidoc-swift against the reference asciidoctor
for a given AsciiDoc source file. The script prefers Hyperfine for
benchmarking and falls back to repeated /usr/bin/time runs if Hyperfine
is unavailable. Customize the commands via:

  ASCIIDOC_SWIFT_BIN=/path/to/asciidoc-swift \
  ASCIIDOCTOR_BIN=/path/to/asciidoctor \
  RUNS=20 \
  scripts/compare-perf.sh doc.adoc

EOF
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

DOC="$1"
if [[ ! -f "$DOC" ]]; then
  echo "error: '$DOC' does not exist" >&2
  exit 1
fi

# Resolve asciidoc-swift binary
SWIFT_BIN="${ASCIIDOC_SWIFT_BIN:-.build/release/asciidoc-swift}"
if [[ ! -x "$SWIFT_BIN" ]]; then
  if command -v asciidoc-swift >/dev/null 2>&1; then
    SWIFT_BIN="$(command -v asciidoc-swift)"
  else
    echo "error: asciidoc-swift binary not found. Build with 'swift build -c release' or set ASCIIDOC_SWIFT_BIN." >&2
    exit 1
  fi
fi

# Resolve asciidoctor binary
ASCIIDOCTOR_BIN="${ASCIIDOCTOR_BIN:-asciidoctor}"
if ! command -v "$ASCIIDOCTOR_BIN" >/dev/null 2>&1; then
  echo "error: asciidoctor command not found. Install it or set ASCIIDOCTOR_BIN." >&2
  exit 1
fi

RUNS="${RUNS:-10}"

swift_cmd="cat \"$DOC\" | \"$SWIFT_BIN\" json-adapter --stdin --plain >/dev/null"
ruby_cmd="\"$ASCIIDOCTOR_BIN\" -o - \"$DOC\" >/dev/null"

if command -v hyperfine >/dev/null 2>&1; then
  echo "Running Hyperfine benchmark ($RUNS runs, 1 warmup)..."
  hyperfine \
    --warmup 1 \
    --min-runs "$RUNS" \
    "$swift_cmd" \
    "$ruby_cmd"
else
  echo "Hyperfine not found; falling back to /usr/bin/time with $RUNS runs each."
  if ! command -v /usr/bin/time >/dev/null 2>&1; then
    echo "error: /usr/bin/time not available for fallback timing." >&2
    exit 1
  fi

  measure() {
    local name="$1"
    local cmd="$2"
    echo "== $name =="
    for ((i=1; i<=RUNS; i++)); do
      /usr/bin/time -f "run %i: %E real  %U user  %S sys" bash -c "$cmd" 2>&1 >/dev/null
    done
  }

  measure "asciidoc-swift" "$swift_cmd"
  measure "asciidoctor" "$ruby_cmd"
fi
