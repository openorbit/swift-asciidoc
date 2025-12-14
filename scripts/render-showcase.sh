#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

DOC_PATH="${1:-${REPO_ROOT}/examples/showcase.adoc}"
OUTPUT_DIR="${2:-${REPO_ROOT}/artifacts/showcase}"
TEMPLATE_ROOT="${TEMPLATES:-${REPO_ROOT}/Templates}"

mkdir -p "${OUTPUT_DIR}"

render() {
  local backend="$1"
  local extension="$2"
  local outfile="${OUTPUT_DIR}/showcase.${extension}"
  echo "→ Rendering ${backend} to ${outfile}"
  swift run -q asciidoc-swift "${backend}" \
    --template "${TEMPLATE_ROOT}" \
    --output "${outfile}" \
    "${DOC_PATH}"
}

render html html
render docbook xml
render latex tex

convert_docbook_pdf() {
  local xml="${OUTPUT_DIR}/showcase.xml"
  if [[ ! -f "${xml}" ]]; then
    echo "⚠︎ DocBook XML not found at ${xml}; skipping DocBook PDF conversion"
    return
  fi
  if ! command -v xsltproc >/dev/null 2>&1; then
    echo "⚠︎ xsltproc not available; skipping DocBook PDF conversion"
    return
  fi
  if ! command -v fop >/dev/null 2>&1; then
    echo "⚠︎ Apache FOP not available; skipping DocBook PDF conversion"
    return
  fi

  local stylesheet="${DOCBOOK_XSL_FO:-}"
  if [[ -z "${stylesheet}" ]]; then
    local candidates=(
      "/opt/homebrew/opt/docbook-xsl/docbook-xsl-ns/fo/docbook.xsl"
      "/usr/local/opt/docbook-xsl/docbook-xsl-ns/fo/docbook.xsl"
      "/usr/share/xml/docbook/stylesheet/docbook-xsl-ns/fo/docbook.xsl"
      "/usr/share/xml/docbook/stylesheet/docbook-xsl/fo/docbook.xsl"
      "/usr/share/xsl/docbook/fo/docbook.xsl"
    )
    for candidate in "${candidates[@]}"; do
      if [[ -f "${candidate}" ]]; then
        stylesheet="${candidate}"
        break
      fi
    done
  fi

  if [[ -z "${stylesheet}" ]]; then
    echo "⚠︎ Could not locate DocBook FO stylesheet. Set DOCBOOK_XSL_FO to override."
    return
  fi

  local fo_output="${OUTPUT_DIR}/showcase.fo"
  local pdf_output="${OUTPUT_DIR}/showcase-docbook.pdf"

  echo "→ Converting DocBook XML to XSL-FO via xsltproc"
  if ! xsltproc --output "${fo_output}" "${stylesheet}" "${xml}"; then
    echo "⚠︎ xsltproc failed; leaving ${fo_output} (if any) for inspection"
    return
  fi

  echo "→ Rendering FO to PDF via Apache FOP"
  if fop "${fo_output}" "${pdf_output}"; then
    echo "✓ DocBook PDF written to ${pdf_output}"
    rm -f "${fo_output}"
  else
    echo "⚠︎ fop failed; FO file retained at ${fo_output}"
  fi
}

convert_docbook_pdf

convert_docbook_html_with_xsltng() {
  local xml="${OUTPUT_DIR}/showcase.xml"
  if [[ ! -f "${xml}" ]]; then
    echo "⚠︎ DocBook XML not found at ${xml}; skipping DocBook HTML via XSLTNG"
    return
  fi

  local stylesheet="${DOCBOOK_XSLTNG_HTML:-}"
  if [[ -z "${stylesheet}" || ! -f "${stylesheet}" ]]; then
    echo "⚠︎ DOCBOOK_XSLTNG_HTML not set or file missing; skipping DocBook HTML via XSLTNG"
    return
  fi

  local saxon_cmd=()
  if [[ -n "${SAXON_CMD:-}" ]]; then
    if command -v "${SAXON_CMD}" >/dev/null 2>&1; then
      saxon_cmd=("${SAXON_CMD}")
    else
      echo "⚠︎ SAXON_CMD=${SAXON_CMD} not found on PATH; skipping XSLTNG render"
      return
    fi
  else
    for candidate in saxon10he saxon9he saxon-he; do
      if command -v "${candidate}" >/dev/null 2>&1; then
        saxon_cmd=("${candidate}")
        break
      fi
    done
  fi

  if [[ ${#saxon_cmd[@]} -eq 0 ]]; then
    if [[ -n "${SAXON_JAR:-}" && -f "${SAXON_JAR}" ]]; then
      saxon_cmd=("java" "-jar" "${SAXON_JAR}")
    else
      echo "⚠︎ Could not locate Saxon (set SAXON_CMD or SAXON_JAR); skipping XSLTNG render"
      return
    fi
  fi

  local html_output="${OUTPUT_DIR}/showcase-docbook.html"
  echo "→ Converting DocBook XML to HTML5 via XSLTNG (${stylesheet})"
  if "${saxon_cmd[@]}" -s:"${xml}" -xsl:"${stylesheet}" -o:"${html_output}"; then
    echo "✓ DocBook HTML written to ${html_output}"
  else
    echo "⚠︎ Saxon/XSLTNG transformation failed; see output above"
  fi
}

convert_docbook_html_with_xsltng

if command -v pdflatex >/dev/null 2>&1; then
  echo "→ pdflatex detected; producing PDF"
  (
    cd "${OUTPUT_DIR}"
    pdflatex -shell-escape -interaction=nonstopmode -halt-on-error showcase.tex >/dev/null
    pdflatex -shell-escape -interaction=nonstopmode -halt-on-error showcase.tex >/dev/null
    mv showcase.pdf showcase-render.pdf
    rm -f showcase.aux showcase.log
  )
  echo "✓ PDF written to ${OUTPUT_DIR}/showcase-render.pdf"
else
  echo "⚠︎ pdflatex not available; skipped PDF generation"
fi

echo
echo "Artifacts:"
ls -1 "${OUTPUT_DIR}"
