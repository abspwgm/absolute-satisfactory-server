#!/bin/bash
# =============================================================================
# E2E: a backup is written, and retention actually drops the oldest
# =============================================================================
# A retention setting that has never dropped anything is a guess, so this
# creates more archives than the limit and asserts the count comes back down.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../test_helpers.sh"

CONTAINER="satisfactory-server"
MAX=3   # BACKUPS_MAX_COUNT in docker-compose.test.yml

log_test_start "backup"

# Give the backup something to find, so the run is not a no-op.
docker exec "${CONTAINER}" sh -c 'mkdir -p /config/saved && echo world > /config/saved/e2e.sav'

for i in $(seq 1 $((MAX + 2))); do
    if ! docker exec "${CONTAINER}" /opt/satisfactory/scripts/backup >/dev/null 2>&1; then
        log_fail "Backup run ${i} failed"
        docker exec "${CONTAINER}" /opt/satisfactory/scripts/backup 2>&1 | tail -10 || true
        exit 1
    fi
    sleep 1   # distinct timestamps
done

count="$(docker exec "${CONTAINER}" sh -c 'ls -1 /config/backups/*.tar.gz 2>/dev/null | wc -l' | tr -d '\r')"
[[ "${count}" =~ ^[0-9]+$ ]] || count=0

if [[ "${count}" -eq "${MAX}" ]]; then
    log_pass "Retention kept exactly ${MAX} archives after $((MAX + 2)) runs"
else
    log_fail "Expected ${MAX} archives after retention, found ${count}"
    docker exec "${CONTAINER}" ls -la /config/backups 2>&1 | tail -10 || true
    exit 1
fi

log_test_pass "backup"
exit 0
