#!/usr/bin/env bash
set -euo pipefail

DB_PATH="${1:-banking.sqlite}"
EMAIL_HTML_PATH="${2:-reports/pipeline-email.html}"
EMAIL_PLAIN_PATH="${3:-reports/pipeline-email-plain.txt}"
EMAIL_SUBJECT_PATH="${4:-reports/pipeline-email-subject.txt}"

REBUILD_OUTCOME="${REBUILD_OUTCOME:-unknown}"
VERIFY_OUTCOME="${VERIFY_OUTCOME:-unknown}"
PIPELINE_NAME="${PIPELINE_NAME:-Database Pipeline}"

mkdir -p "$(dirname "${EMAIL_HTML_PATH}")"
mkdir -p "$(dirname "${EMAIL_PLAIN_PATH}")"
mkdir -p "$(dirname "${EMAIL_SUBJECT_PATH}")"

pipeline_success="false"
if [[ "${REBUILD_OUTCOME}" == "success" && "${VERIFY_OUTCOME}" == "success" ]]; then
  pipeline_success="true"
fi

if [[ "${pipeline_success}" == "true" ]]; then
  bash scripts/generate_email_health_report.sh "${DB_PATH}" "${EMAIL_HTML_PATH}" "${EMAIL_PLAIN_PATH}"
  printf '[%s] Database health report - SUCCESS\n' "${PIPELINE_NAME}" > "${EMAIL_SUBJECT_PATH}"
  echo "Prepared rendered success email at ${EMAIL_HTML_PATH}"
  exit 0
fi

bash scripts/generate_email_failure_report.sh \
  "${DB_PATH}" \
  "${EMAIL_HTML_PATH}" \
  "${EMAIL_PLAIN_PATH}" \
  "reports/rebuild.log" \
  "reports/verify.log" \
  "reports/db-verification-failures.tsv"

printf '[%s] Database pipeline failure report - ACTION REQUIRED\n' "${PIPELINE_NAME}" > "${EMAIL_SUBJECT_PATH}"
echo "Prepared rendered failure email at ${EMAIL_HTML_PATH}"
