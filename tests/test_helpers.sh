#!/bin/bash
# =============================================================================
# Shared test helpers
# =============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_pass()    { echo -e "${GREEN}[PASS]${NC} $*"; }
log_fail()    { echo -e "${RED}[FAIL]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }

log_test_start() {
    echo ""
    echo "----------------------------------------"
    echo "Starting test: $1"
    echo "----------------------------------------"
}

log_test_pass() {
    echo -e "${GREEN}Test PASSED: $1${NC}"
}

log_test_fail() {
    echo -e "${RED}Test FAILED: $1${NC}"
}

# Every unit test collects failures rather than stopping at the first, so one
# run shows the whole distance.
CHECKS_FAILED=0

check() {
    local description="$1"
    shift
    if "$@"; then
        log_pass "${description}"
    else
        log_fail "${description}"
        CHECKS_FAILED=$((CHECKS_FAILED + 1))
    fi
}

finish() {
    local name="$1"
    if [[ ${CHECKS_FAILED} -gt 0 ]]; then
        log_test_fail "${name}: ${CHECKS_FAILED} check(s) failed"
        exit 1
    fi
    log_test_pass "${name}"
    exit 0
}

# Builds a valid manifest in ${1}, overriding any KEY=VALUE given after it.
write_manifest() {
    local path="$1"
    shift
    mkdir -p "$(dirname "${path}")"
    cat > "${path}" <<'MANIFEST'
GAME_ID=example
GAME_NAME="Example Server"
STEAM_APP_ID=896660
STEAM_LOGIN=anonymous
STEAM_BRANCH=public
STEAM_PLATFORM=linux
SERVER_BINARY=ExampleServer.sh
SERVER_PROCESS=ExampleServer-Linux-Shipping
STOP_SIGNAL=INT
STOP_TIMEOUT=90
READY_LOG_PATTERN='Server startup complete'
PUBLIC_PORTS=7777/udp
PRIVATE_PORTS=
SAVE_PATHS=saves
SNAPSHOT_PATHS=/opt/example/server
ADMIN_PASSWORD_VAR=
MOD_SOURCE=
MOD_EXPECT_PLUGINS=0
MANIFEST
    local override
    for override in "$@"; do
        local key="${override%%=*}"
        # Replace the line if present, append if not.
        if grep -q "^${key}=" "${path}"; then
            local escaped="${override//\//\\/}"
            sed -i "s/^${key}=.*/${escaped}/" "${path}"
        else
            echo "${override}" >> "${path}"
        fi
    done
}

# -----------------------------------------------------------------------------
# The server's API, from the host
# -----------------------------------------------------------------------------
# Two of the e2e tests ask the server what it is the way a joining player's
# game does, independently of the image's own client in scripts/common, so that
# two implementations have to agree. Both need a token: QueryServerState asked
# without one is answered "insufficient_scope" - with HTTP 200, and no state -
# which the first ladder run (35791204112) read as silence, ten times over.

# host_api <function> [data-json] [token] ; the body, whatever the status
host_api() {
    local fn="$1" data="${2:-{\}}" token="${3:-}" auth=()
    [[ -n "${token}" ]] && auth=(-H "Authorization: Bearer ${token}")
    curl -sk -m 15 -X POST "https://127.0.0.1:${SERVER_PORT:-7777}/api/v1" \
        -H 'Content-Type: application/json' "${auth[@]}" \
        --data "$(printf '{"function":"%s","data":%s}' "${fn}" "${data}")" 2>/dev/null
}

# host_server_state ; QueryServerState as a joining player's game asks it: a
# Client token from a passwordless login first, which the server grants while
# it has no client password, then the question. Nothing when no token came.
host_server_state() {
    local token
    token="$(host_api PasswordlessLogin '{"MinimumPrivilegeLevel":"Client"}' \
        | jq -r '.data.authenticationToken // .data.AuthenticationToken // empty' 2>/dev/null)"
    [[ -n "${token}" ]] || return 1
    host_api QueryServerState '{}' "${token}"
}
