#!/bin/bash
# =============================================================================
# E2E: reachable (ready ladder rung 2, standard 2.10)
# Both game ports are bound, and the server's own API answers a health check
# from outside the container.
# =============================================================================
# server_start proves a process is up and the UDP port is bound. Reachable is
# the next thing along: that something outside the container gets an answer
# back. The call goes over the published port from the runner, not through
# `docker exec`, so it crosses the same boundary a player's client does.
#
# The API is TLS with the server's own self-signed certificate, so curl is told
# not to verify it (-k). What is being proven is that the server answers, not
# who signed its certificate.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../test_helpers.sh"

CONTAINER="satisfactory-server"
PORT="${SERVER_PORT:-7777}"
# The API can answer a little after the port binds; the world is still loading.
DEADLINE="${API_DEADLINE:-600}"

log_test_start "server_query"

# Which ports the container actually holds, read from the kernel's own tables.
# `ss` is not installed in this image family (scripts/common), and mawk on the
# runner has no strtonum, so the hex is decoded in bash.
container_ports() {
    local proto="$1" addr ports=""
    while read -r _ addr _; do
        [[ "${addr}" == *:* ]] || continue
        ports+="$(( 16#${addr##*:} )) "
    done < <(MSYS_NO_PATHCONV=1 docker exec "${CONTAINER}" sh -c \
        "cat /proc/net/${proto} /proc/net/${proto}6 2>/dev/null; exit 0" 2>/dev/null | tail -n +2)
    tr ' ' '\n' <<< "${ports}" | sort -un | tr '\n' ' '
}

failed=0
for proto in udp tcp; do
    held="$(container_ports "${proto}")"
    if grep -qw "${PORT}" <<< "${held}"; then
        log_pass "${PORT}/${proto} is bound"
    else
        log_fail "${PORT}/${proto} is not bound; the container holds: ${held:-none}"
        failed=1
    fi
done

# One POST, no token: HealthCheck is the call a monitoring tool makes.
health=""
waited=0
while [[ ${waited} -lt ${DEADLINE} ]]; do
    health="$(curl -sk -m 15 -X POST "https://127.0.0.1:${PORT}/api/v1" \
        -H 'Content-Type: application/json' \
        --data '{"function":"HealthCheck","data":{"ClientCustomData":""}}' 2>/dev/null)" || true
    [[ -n "$(jq -r '.data.health // .data.Health // empty' <<< "${health}" 2>/dev/null)" ]] && break
    sleep 15
    waited=$((waited + 15))
done

reported="$(jq -r '.data.health // .data.Health // empty' <<< "${health}" 2>/dev/null)"
if [[ -n "${reported}" ]]; then
    log_pass "The server's API answered a health check from outside the container: ${reported}"
else
    log_fail "The server's API never answered on ${PORT}/tcp within ${DEADLINE}s"
    log_info "Last answer: ${health:-<nothing>}"
    # The repository's own notes call 8888/tcp the management API. If that is
    # where it lives, this says so rather than leaving the next reader guessing.
    alt="$(curl -sk -m 10 -X POST "https://127.0.0.1:8888/api/v1" \
        -H 'Content-Type: application/json' \
        --data '{"function":"HealthCheck","data":{"ClientCustomData":""}}' 2>/dev/null)" || true
    log_info "8888/tcp answered: ${alt:-<nothing>}"
    failed=1
fi

if [[ ${failed} -ne 0 ]]; then
    dump_container_logs "${CONTAINER}" 40
    log_test_fail "server_query"
    exit 1
fi

log_test_pass "server_query"
exit 0
