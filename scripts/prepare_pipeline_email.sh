#!/usr/bin/env bash
set -euo pipefail

DB_PATH="${1:-banking.sqlite}"
EMAIL_HTML_PATH="${2:-reports/pipeline-email.html}"
EMAIL_SUBJECT_PATH="${3:-reports/pipeline-email-subject.txt}"

REBUILD_OUTCOME="${REBUILD_OUTCOME:-unknown}"
VERIFY_OUTCOME="${VERIFY_OUTCOME:-unknown}"
PIPELINE_NAME="${PIPELINE_NAME:-Database Pipeline}"

mkdir -p "$(dirname "${EMAIL_HTML_PATH}")"
mkdir -p "$(dirname "${EMAIL_SUBJECT_PATH}")"

pipeline_success="false"
if [[ "${REBUILD_OUTCOME}" == "success" && "${VERIFY_OUTCOME}" == "success" ]]; then
  pipeline_success="true"
fi

if [[ "${pipeline_success}" == "true" ]]; then
  if [[ ! -f "reports/db-health-report.html" ]]; then
    make db-report DB_FILE="${DB_PATH}" >/dev/null
  fi
  cp "reports/db-health-report.html" "${EMAIL_HTML_PATH}"
  printf '[%s] Database health report - SUCCESS\n' "${PIPELINE_NAME}" > "${EMAIL_SUBJECT_PATH}"
  echo "Prepared success email using reports/db-health-report.html"
  exit 0
fi

bash scripts/generate_failure_report.sh \
  "${DB_PATH}" \
  "reports/db-failure-report.html" \
  "reports/rebuild.log" \
  "reports/verify.log" \
  "reports/db-verification-failures.tsv"

cp "reports/db-failure-report.html" "${EMAIL_HTML_PATH}"
printf '[%s] Database pipeline failure report - ACTION REQUIRED\n' "${PIPELINE_NAME}" > "${EMAIL_SUBJECT_PATH}"
echo "Prepared failure email using reports/db-failure-report.html"
