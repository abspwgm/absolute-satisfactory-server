#!/bin/bash
# =============================================================================
# Runs every unit test. No Docker, no network, under a second.
# This is the fast tier: a contributor gets a signal before they lose the thread.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test_helpers.sh"

FAILED=()
for test_file in "${SCRIPT_DIR}"/unit/test_*.sh; do
    if ! bash "${test_file}"; then
        FAILED+=("$(basename "${test_file}")")
    fi
done

echo ""
if [[ ${#FAILED[@]} -gt 0 ]]; then
    log_fail "${#FAILED[@]} suite(s) failed: ${FAILED[*]}"
    exit 1
fi
log_pass "every unit suite passed"
exit 0
