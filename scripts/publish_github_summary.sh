#!/usr/bin/env bash
set -euo pipefail

HTML_REPORT="${1:-reports/db-health-report.html}"
MARKDOWN_REPORT="${2:-reports/db-health-report.md}"

if [[ -z "${GITHUB_STEP_SUMMARY:-}" ]]; then
  echo "GITHUB_STEP_SUMMARY is not set; skipping workflow summary publish."
  exit 0
fi

if [[ ! -f "${HTML_REPORT}" ]]; then
  echo "Error: HTML report not found at ${HTML_REPORT}" >&2
  exit 1
fi

{
  echo "# Database Health Report"
  echo
  echo "The pipeline generated a self-contained HTML health dashboard with schema, integrity, and ledger details."
  echo
  if [[ -f "${MARKDOWN_REPORT}" ]]; then
    echo "## Quick Summary"
    echo
    sed -n '/^## Row Counts/,/^## Latest Transactions/p' "${MARKDOWN_REPORT}" | sed '$d'
    echo
  fi
  echo "## HTML Report"
  echo
  echo "The full responsive report is embedded below and attached as a workflow artifact."
  echo
  cat "${HTML_REPORT}"
} >> "${GITHUB_STEP_SUMMARY}"

echo "Published HTML report to GitHub workflow summary."
