#!/bin/bash
# =============================================================================
# E2E: discoverable (ready ladder rung 3, standard 2.10)
# The server tells a client that asks it what it is: a running game, a session
# name, a player limit and a live player count.
# =============================================================================
# Satisfactory has no server browser. A player adds a server by address, and
# the client then asks that address what it is - QueryServerState over the
# same HTTPS API, with the Client token a passwordless login grants while the
# server has no client password. That answer is what the player sees in their
# server manager, so answering it correctly is this game's whole meaning of
# "discoverable": there is no list to be listed in.
#
# The token is not optional. Asked without one, the server answers
# "insufficient_scope" - with HTTP 200, and no serverGameState - which the
# first ladder run (35791204112) reported as "the server did not say what it
# is". It had said something; the question was wrong.
#
# The count the server advertises is cross-checked against the one the image's
# own helper reads, so two independent views of one fact have to agree - the
# helper the updater's idle guard will call, not a second copy of this query.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../test_helpers.sh"

CONTAINER="satisfactory-server"
PORT="${SERVER_PORT:-7777}"
DEADLINE="${API_DEADLINE:-600}"

log_test_start "discoverable"

state=""
waited=0
while [[ ${waited} -lt ${DEADLINE} ]]; do
    state="$(host_server_state)" || true
    [[ -n "$(jq -r '.data.serverGameState // empty' <<< "${state}" 2>/dev/null)" ]] && break
    sleep 15
    waited=$((waited + 15))
done

game_state="$(jq -c '.data.serverGameState // empty' <<< "${state}" 2>/dev/null)"
if [[ -z "${game_state}" ]]; then
    log_fail "The server did not say what it is when asked (QueryServerState)"
    log_info "Last answer: ${state:-<nothing>}"
    docker logs "${CONTAINER}" --tail 40 2>&1 || true
    log_test_fail "discoverable"
    exit 1
fi

session="$(jq -r '.activeSessionName // ""' <<< "${game_state}")"
running="$(jq -r '.isGameRunning // false' <<< "${game_state}")"
limit="$(jq -r '.playerLimit // 0' <<< "${game_state}")"
players="$(jq -r '.numConnectedPlayers // "?"' <<< "${game_state}")"
log_info "A client asking this address sees: session='${session}' running=${running} players=${players}/${limit}"

failed=0
if [[ "${running}" == "true" ]]; then
    log_pass "It reports a running game, not just a listening socket"
else
    log_fail "It answers, but reports no running game (isGameRunning=${running})"
    failed=1
fi
if [[ "${limit}" =~ ^[0-9]+$ ]] && [[ "${limit}" -gt 0 ]]; then
    log_pass "It advertises room for ${limit} players"
else
    log_fail "It advertises a player limit of '${limit}'"
    failed=1
fi
if [[ -n "${session}" ]]; then
    log_pass "It names its session: '${session}'"
else
    log_fail "It names no session, so a player's server manager shows a blank entry"
    failed=1
fi

# The same number, read the way the image reads it.
counted="$(MSYS_NO_PATHCONV=1 docker exec "${CONTAINER}" bash -c \
    'source /opt/satisfactory/scripts/common && get_player_count' 2>/dev/null)" || true
if [[ "${counted}" =~ ^[0-9]+$ ]] && [[ "${counted}" == "${players}" ]]; then
    log_pass "The advertised player count (${players}) matches the one the image reads (${counted})"
else
    log_fail "It advertises ${players} players; the image's own helper says '${counted:-<nothing>}'"
    failed=1
fi

if [[ ${failed} -ne 0 ]]; then
    log_test_fail "discoverable"
    exit 1
fi

log_test_pass "discoverable"
exit 0
