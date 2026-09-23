#!/bin/bash
# =============================================================================
# E2E: the server comes back, with the world it was stopped with
# =============================================================================
# This runs after graceful_shutdown, on the container it stopped. Starting
# again is half the point; the other half is that the world survives. The
# server is asked what session it is running, and it has to be the one that
# was created and saved before the stop - a server that comes back empty has
# lost the save, which looks identical to a healthy start from the outside.
#
# UPDATE_ON_START is true in the test compose file, so the start also runs the
# updater against Steam. A start that updates and then loads the world is the
# recoverable rung's real question: after an update, is the game still there?
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../test_helpers.sh"

PROJECT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
COMPOSE="docker compose -f ${PROJECT_DIR}/docker-compose.test.yml"
CONTAINER="satisfactory-server"
PORT="${SERVER_PORT:-7777}"
EXPECTED_SESSION="E2E Session"
DEADLINE="${RESTART_DEADLINE:-900}"

log_test_start "restart_update"

failed=0

log_info "Starting the container again"
if ${COMPOSE} up -d >/dev/null 2>&1; then
    log_pass "The container started"
else
    log_fail "The container would not start again"
    ${COMPOSE} logs --tail 40 2>&1 || true
    log_test_fail "restart_update"
    exit 1
fi

# Wait for the API, which only answers once the server is up and the update
# (UPDATE_ON_START) has finished - and ask it as a player would, with a token.
state=""
waited=0
while [[ ${waited} -lt ${DEADLINE} ]]; do
    state="$(host_server_state)" || true
    [[ "$(jq -r '.data.serverGameState.isGameRunning // false' <<< "${state}" 2>/dev/null)" == "true" ]] && break
    sleep 15
    waited=$((waited + 15))
done

running="$(jq -r '.data.serverGameState.isGameRunning // false' <<< "${state}" 2>/dev/null)"
session="$(jq -r '.data.serverGameState.activeSessionName // ""' <<< "${state}" 2>/dev/null)"

if [[ "${running}" == "true" ]]; then
    log_pass "The server is running a game again after ${waited}s"
else
    log_fail "The server never reported a running game within ${DEADLINE}s of restarting"
    dump_container_logs "${CONTAINER}" 40
    failed=1
fi

if [[ "${session}" == "${EXPECTED_SESSION}" ]]; then
    log_pass "It came back with the world it was stopped with: '${session}'"
else
    log_fail "Expected the session '${EXPECTED_SESSION}', the server is running '${session:-<none>}'"
    failed=1
fi

# It must also be up in the sense the health check means, not just answering.
if docker exec "${CONTAINER}" /opt/satisfactory/scripts/healthcheck >/dev/null 2>&1; then
    log_pass "The health check agrees"
else
    log_fail "The health check disagrees with a server that answers its API"
    docker exec "${CONTAINER}" /opt/satisfactory/scripts/healthcheck 2>&1 || true
    failed=1
fi

if [[ ${failed} -ne 0 ]]; then
    log_test_fail "restart_update"
    exit 1
fi

log_test_pass "restart_update"
exit 0
