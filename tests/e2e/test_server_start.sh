#!/bin/bash
# =============================================================================
# E2E: the server starts, stays up, and binds its port
# =============================================================================
# Readiness is a capability, not a log line. Matching a startup string means
# guessing which one this build prints, and a wrong guess reports a failure
# that never happened - the sibling repositories lost a day to exactly that.
# A bound game port is the closest observable thing to "a player could join".
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../test_helpers.sh"

CONTAINER="satisfactory-server"
PORT="${SERVER_PORT:-7777}"
DEADLINE="${SERVER_START_DEADLINE:-2400}"

# The container's UDP socket table, parsed on this side. This used `ss` inside
# the container, which no image in this family installs: the probe's stderr went
# to /dev/null, grep saw nothing, and the port "never bound" however healthy the
# server was - run 35532327931 reached "InitBase GameNetDriver" in two seconds
# and still timed out after forty minutes. /proc/net is always there. `exit 0`
# because udp6 is absent on a host with IPv6 off, and pipefail would otherwise
# fail a port found in udp.
port_bound() {
    docker exec "${CONTAINER}" sh -c 'cat /proc/net/udp; cat /proc/net/udp6 2>/dev/null; exit 0' 2>/dev/null \
        | awk -v suffix=":$(printf '%04X' "$1")" 'toupper($2) ~ (suffix "$") { found = 1 } END { exit !found }'
}

log_test_start "server_start"

waited=0
while [[ ${waited} -lt ${DEADLINE} ]]; do
    if ! docker ps --format '{{.Names}}' | grep -qx "${CONTAINER}"; then
        log_fail "Container stopped during startup"
        dump_container_logs "${CONTAINER}" 40
        exit 1
    fi
    if port_bound "${PORT}"; then
        log_pass "The game port ${PORT}/udp is bound after ${waited}s"
        break
    fi
    sleep 15
    waited=$((waited + 15))
done

if [[ ${waited} -ge ${DEADLINE} ]]; then
    log_fail "The game port never bound within ${DEADLINE}s"
    dump_container_logs "${CONTAINER}" 60
    exit 1
fi

# Supervisor supervises the game itself here, so an exit is an exit: if the
# process has been restarting, supervisor says so rather than a wrapper hiding
# it (abspwgm/absolute-rust-server#13).
restarts="$(docker logs "${CONTAINER}" 2>&1 | grep -c "spawned: 'game'" || true)"
[[ "${restarts}" =~ ^[0-9]+$ ]] || restarts=0
if [[ "${restarts}" -gt 1 ]]; then
    log_fail "The game was spawned ${restarts} times: it is restarting, not running"
    dump_container_logs "${CONTAINER}" 60
    exit 1
fi
log_pass "The game was started once and stayed up"

if docker exec "${CONTAINER}" /opt/satisfactory/scripts/healthcheck >/dev/null 2>&1; then
    log_pass "The health check agrees"
else
    log_fail "The health check disagrees with a bound port"
    docker exec "${CONTAINER}" /opt/satisfactory/scripts/healthcheck 2>&1 || true
    exit 1
fi

log_test_pass "server_start"
exit 0
