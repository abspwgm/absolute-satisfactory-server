#!/bin/bash
# =============================================================================
# E2E: authenticated (ready ladder rung 4, standard 2.10)
# The server is claimed, a world is created, and an admin session logs in with
# the password that claim set and does something only an admin may do.
# =============================================================================
# A fresh Satisfactory server has no admin and no world: the first client to
# connect claims it, sets the admin password and creates the session. Until
# that happens the server answers "no game running" and nobody can play, so
# this test does what that first client does, over the same API:
#
#   1. passwordless login, which only an unclaimed server grants, at
#      InitialAdmin - the claim path, and proof the server is genuinely fresh
#   2. ClaimServer with a name and an admin password
#   3. CreateNewGame, which is what makes the world a player joins
#   4. a fresh PasswordLogin with that password, and an admin-only call
#   5. the same login with a wrong password, which must be refused
#
# It runs before discoverable for that reason: there is nothing to discover
# until a world exists. This is a real authenticated session, not a stand-in:
# the token is the one the game's own client gets. What it is not is a player
# joining the world - no headless Satisfactory client exists - so the rung is
# "an admin session on the server's API", and the verdict says exactly that.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../test_helpers.sh"

CONTAINER="satisfactory-server"
PORT="${SERVER_PORT:-7777}"
API="https://127.0.0.1:${PORT}/api/v1"
# Must match ADMIN_PASSWORD and SESSION_NAME in docker-compose.test.yml: the
# image reads them to save the world before it stops.
ADMIN_PASSWORD="${E2E_ADMIN_PASSWORD:-e2e-admin-pw}"
SERVER_NAME="Absolute E2E"
SESSION_NAME="E2E Session"
DEADLINE="${API_DEADLINE:-600}"

# api <function> <data-json> [token] [timeout] ; body on 2xx, nothing otherwise
api() {
    local fn="$1" data="$2" token="${3:-}" timeout="${4:-30}" auth=() body code
    [[ -n "${token}" ]] && auth=(-H "Authorization: Bearer ${token}")
    body="$(mktemp)"
    code="$(curl -sk -m "${timeout}" -X POST "${API}" \
        -H 'Content-Type: application/json' "${auth[@]}" \
        --data "$(printf '{"function":"%s","data":%s}' "${fn}" "${data}")" \
        -o "${body}" -w '%{http_code}' 2>/dev/null)" || true
    API_STATUS="${code:-000}"
    API_BODY="$(cat "${body}" 2>/dev/null)"
    rm -f "${body}"
    [[ "${API_STATUS}" =~ ^2[0-9][0-9]$ ]]
}

# Tokens come back as authenticationToken; the field's case has moved between
# builds, so both spellings are accepted rather than failing on a capital A.
token_of() { jq -r '.data.authenticationToken // .data.AuthenticationToken // empty' <<< "$1"; }

log_test_start "authenticated"

# The API has to be up before any of this means anything.
waited=0
until api HealthCheck '{"ClientCustomData":""}' "" 15; do
    if [[ ${waited} -ge ${DEADLINE} ]]; then
        log_fail "The server's API never answered within ${DEADLINE}s"
        docker logs "${CONTAINER}" --tail 40 2>&1 || true
        log_test_fail "authenticated"
        exit 1
    fi
    sleep 15
    waited=$((waited + 15))
done

failed=0

# 1. Passwordless login. An unclaimed server grants InitialAdmin; a claimed one
#    refuses, which would mean this run started on someone else's world.
if api PasswordlessLogin '{"MinimumPrivilegeLevel":"InitialAdmin"}'; then
    initial_token="$(token_of "${API_BODY}")"
fi
if [[ -z "${initial_token:-}" ]]; then
    log_fail "The server did not grant an initial admin token (HTTP ${API_STATUS}): ${API_BODY:0:200}"
    log_test_fail "authenticated"
    exit 1
fi
log_pass "The server granted the claim token an unclaimed server grants"

# 2. Claim it: this is what sets the admin password.
if api ClaimServer "$(jq -nc --arg n "${SERVER_NAME}" --arg p "${ADMIN_PASSWORD}" \
        '{ServerName: $n, AdminPassword: $p}')" "${initial_token}" 60; then
    log_pass "Claimed the server as '${SERVER_NAME}'"
else
    log_fail "The claim was refused (HTTP ${API_STATUS}): ${API_BODY:0:200}"
    log_test_fail "authenticated"
    exit 1
fi

# 3. An admin session with the password the claim just set. This is the rung.
if api PasswordLogin "$(jq -nc --arg p "${ADMIN_PASSWORD}" \
        '{MinimumPrivilegeLevel: "Administrator", Password: $p}')" "" 60; then
    admin_token="$(token_of "${API_BODY}")"
fi
if [[ -n "${admin_token:-}" ]]; then
    log_pass "Logged in as an administrator with the password the claim set"
else
    log_fail "The admin login was refused (HTTP ${API_STATUS}): ${API_BODY:0:200}"
    log_test_fail "authenticated"
    exit 1
fi

# 4. Create the world. Only an administrator may, and without it there is no
#    game to join, so this doubles as an admin-only action that changes state.
# The server answers this one only once the world exists, and generating it
# takes minutes; the first run waited 300s and got no answer at all while every
# read answered at once. So the request is judged by its effect below - a world
# that is running - and a lost connection is reported, not failed on.
if api CreateNewGame "$(jq -nc --arg s "${SESSION_NAME}" \
        '{NewGameData: {SessionName: $s, MapName: "", StartingLocation: "", bSkipOnboarding: true, AdvancedGameSettings: {}}}')" \
        "${admin_token}" "${CREATE_TIMEOUT:-900}"; then
    log_pass "Created the world '${SESSION_NAME}' with the admin session"
elif [[ "${API_STATUS}" == "000" ]]; then
    log_info "No answer to the create request within the wait; checking whether the world came up anyway"
else
    log_fail "Creating the world was refused (HTTP ${API_STATUS}): ${API_BODY:0:200}"
    failed=1
fi

# The world takes a while to generate and load; the session is what a player
# then sees, and this is now the test of whether the creation worked.
waited=0
while [[ ${waited} -lt ${CREATE_DEADLINE:-1200} ]]; do
    if api QueryServerState '{}' "" 15; then
        running="$(jq -r '.data.serverGameState.isGameRunning // false' <<< "${API_BODY}")"
        [[ "${running}" == "true" ]] && break
    fi
    sleep 15
    waited=$((waited + 15))
done
if [[ "${running:-false}" == "true" ]]; then
    log_pass "The server reports a running game after ${waited}s"
else
    log_fail "The world never started within ${CREATE_DEADLINE:-1200}s of being created"
    docker logs "${CONTAINER}" --tail 40 2>&1 || true
    failed=1
fi

# 5. A wrong password must be refused. A login that accepts anything proves
#    nothing about the one that accepted the right password.
if api PasswordLogin '{"MinimumPrivilegeLevel":"Administrator","Password":"not-the-admin-password"}' "" 30 \
    && [[ -n "$(token_of "${API_BODY}")" ]]; then
    log_fail "A wrong admin password was accepted"
    failed=1
else
    log_pass "A wrong admin password is refused (HTTP ${API_STATUS})"
fi

# The image must be able to do this too: the stop path saves the world through
# the same login, using ADMIN_PASSWORD from the environment.
if MSYS_NO_PATHCONV=1 docker exec "${CONTAINER}" bash -c \
        'source /opt/satisfactory/scripts/common && admin_token >/dev/null' 2>/dev/null; then
    log_pass "The image can log in as administrator with its own ADMIN_PASSWORD"
else
    log_fail "The image could not log in with ADMIN_PASSWORD, so it cannot save before stopping"
    failed=1
fi

if [[ ${failed} -ne 0 ]]; then
    log_test_fail "authenticated"
    exit 1
fi

log_test_pass "authenticated"
exit 0
