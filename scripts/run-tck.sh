#!/usr/bin/env bash
set -euo pipefail

# Build CLI shim
swift build -c debug

# Get or update TCK
if [ ! -d .tck ]; then
  git clone --depth=1 https://gitlab.eclipse.org/eclipse/asciidoc-lang/asciidoc-tck.git .tck
else
  git -C .tck pull --ff-only || true
fi

export TCK_ROOT=$(pwd)
export ASCIIDOC_CLI="$(pwd)/scripts/run-adoc-swift.sh"
# Run with Node test runner
cd .tck
#npm ci
#npm run dist

node harness/bin/asciidoc-tck.js cli --adapter-command ${ASCIIDOC_CLI}

