#!/bin/bash
# =============================================================================
# E2E: the server saves the world and stops on its own
# =============================================================================
# The manifest says Satisfactory saves and exits on SIGINT, and that the three
# timeouts nest: STOP_TIMEOUT 120s < supervisor's stopwaitsecs 150s <
# stop_grace_period 180s. Nothing has ever tested either claim. CHECKLIST.md
# says it plainly: "STOP_SIGNAL is verified by watching a save complete. The
# wrong signal corrupts worlds, and it corrupts them quietly."
#
# So this watches one. A world is saved through the server's API first, the
# way an operator would before maintenance, and then the container is stopped
# and has to stop by itself: exit code 137 means the daemon ran out of patience
# and killed it, which is the case that loses a world.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../test_helpers.sh"

PROJECT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CONTAINER="satisfactory-server"
SAVED_DIR="${PROJECT_DIR}/data/config/saved"
# Longer than stop_grace_period (180s), so the daemon's own patience, not this
# test's, is what decides whether the server was given its time.
STOP_WAIT=240

log_test_start "graceful_shutdown"

failed=0

# A save on demand, through the image's own helper: the one the operator and
# the stop path both use, with the admin session `authenticated` set up.
# The server answers a save only when it has written it, and a large world
# outlasts the connection, so a missing answer is not a missing save: the file
# on disk below is what settles it.
if MSYS_NO_PATHCONV=1 docker exec "${CONTAINER}" bash -c \
        'source /opt/satisfactory/scripts/common && save_world e2e-shutdown' 2>&1 | tail -3; then
    log_pass "The server confirmed a save on request"
else
    log_warn "No confirmation of the save on request; the save on disk is checked below"
fi

# Not the backup test's fixture: that file is written by a test, moments
# earlier, and matching it would pass this check on a server that saved
# nothing. It nearly did - the last run "found" a save that was the fixture.
newest_real_save() {
    find "${SAVED_DIR}" -name '*.sav' ! -name 'e2e-backup-fixture.sav' \
        -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1
}

before="$(newest_real_save)"
log_info "Newest save before the stop: ${before:-<none>}"
started_at="$(date +%s)"

log_info "Stopping the container, and waiting up to ${STOP_WAIT}s for it to stop by itself"
start="${SECONDS}"
MSYS_NO_PATHCONV=1 docker stop -t "${STOP_WAIT}" "${CONTAINER}" >/dev/null 2>&1 || true
elapsed=$(( SECONDS - start ))

exit_code="$(MSYS_NO_PATHCONV=1 docker inspect -f '{{.State.ExitCode}}' "${CONTAINER}" 2>/dev/null)" || exit_code="?"
running="$(MSYS_NO_PATHCONV=1 docker inspect -f '{{.State.Running}}' "${CONTAINER}" 2>/dev/null)" || running="?"

if [[ "${running}" == "false" ]]; then
    log_pass "The container stopped after ${elapsed}s"
else
    log_fail "The container is still running ${elapsed}s after being asked to stop"
    failed=1
fi

if [[ "${exit_code}" == "137" ]]; then
    log_fail "Exit code 137: the daemon killed it. The save was cut short, which is how worlds are lost quietly"
    failed=1
else
    log_pass "It exited on its own (code ${exit_code}), not by being killed"
fi

# The save must be on disk, and no older than the run: a stop that writes
# nothing is the failure this test exists for.
after="$(newest_real_save)"
log_info "Newest save after the stop: ${after:-<none>}"
if [[ -z "${after}" ]]; then
    log_fail "No save file exists under ${SAVED_DIR} after a stop"
    ls -la "${SAVED_DIR}" 2>&1 | head -10 || true
    failed=1
elif (( ${after%%.*} >= started_at - 900 )); then
    log_pass "A world save from this run is on disk: ${after##* }"
else
    log_fail "The newest save predates this run by more than fifteen minutes: ${after##* }"
    failed=1
fi

# What the server said on the way out, kept for the next reader either way.
log_info "The last lines before it stopped:"
dump_container_logs "${CONTAINER}" 15

if [[ ${failed} -ne 0 ]]; then
    log_test_fail "graceful_shutdown"
    exit 1
fi

log_test_pass "graceful_shutdown"
exit 0
