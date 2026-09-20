#!/bin/bash
# =============================================================================
# End-to-end suite: build, start, assert, tear down.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"
source "${SCRIPT_DIR}/test_helpers.sh"

COMPOSE="docker compose -f ${PROJECT_DIR}/docker-compose.test.yml"
TESTS=(server_start backup)
FAILED=()

cleanup() {
    log_info "Tearing down"
    ${COMPOSE} down -v >/dev/null 2>&1 || true
}
trap cleanup EXIT

cd "${PROJECT_DIR}"
mkdir -p data/server data/config data/logs

log_info "Starting the stack"
${COMPOSE} up -d

for name in "${TESTS[@]}"; do
    script="${SCRIPT_DIR}/e2e/test_${name}.sh"
    if [[ ! -f "${script}" ]]; then
        log_warn "No such test: ${name}"
        continue
    fi
    log_info "=== ${name} ==="
    if bash "${script}"; then
        log_pass "${name}"
    else
        log_fail "${name}"
        FAILED+=("${name}")
        mkdir -p data/logs
        docker logs satisfactory-server > "data/logs/${name}_FAILED.log" 2>&1 || true
    fi
done

echo ""
if [[ ${#FAILED[@]} -gt 0 ]]; then
    log_fail "Failed: ${#FAILED[@]} (${FAILED[*]})"
    exit 1
fi
log_pass "Every test passed"
exit 0
