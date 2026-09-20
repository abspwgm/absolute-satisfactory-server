#!/bin/bash
# =============================================================================
# Unit Test: process matching (no Docker, no network)
# A shell whose own command line contains the literal process name matches
# itself, so `pkill -f <name>` from that shell kills the shell instead of the
# server. The bracket trick is the fix, and this is the test that keeps it.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$(dirname "${SCRIPT_DIR}")")"

source "${SCRIPT_DIR}/../test_helpers.sh"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

MANIFEST="${WORK_DIR}/manifest.env"

pattern_for() {
    write_manifest "${MANIFEST}" "SERVER_PROCESS=$1"
    (
        export TEST_ROOT="${WORK_DIR}/root"
        export MANIFEST_FILE="${MANIFEST}"
        source "${PROJECT_DIR}/scripts/common"
        server_process_pattern
    ) 2>/dev/null
}

log_test_start "process_pattern (unit)"

PATTERN="$(pattern_for 'valheim_server.x86_64')"
check "the pattern brackets the second character" test "${PATTERN}" == 'v[a]lheim_server.x86_64'
check "the pattern does not contain the plain name" \
    bash -c "[[ '${PATTERN}' != *'valheim_server.x86_64'* ]]"

# The point of the trick: a command line containing the pattern does not match
# the pattern, so a shell running it never matches itself.
sleep 30 &
SLEEP_PID=$!
check "a real process is matched by its pattern" bash -c "
    exec -a 'valheim_server.x86_64' sleep 30 &
    server_pid=\$!
    sleep 0.3
    pgrep -f '${PATTERN}' | grep -q \"\${server_pid}\"
    result=\$?
    kill \${server_pid} 2>/dev/null
    exit \${result}
"
kill "${SLEEP_PID}" 2>/dev/null

check "a shell whose command line holds the pattern does not match it" bash -c "
    bash -c 'sleep 2 # ${PATTERN}' &
    decoy=\$!
    sleep 0.3
    matched=\$(pgrep -f '${PATTERN}' | grep -c \"\${decoy}\" || true)
    kill \${decoy} 2>/dev/null
    test \"\${matched}\" -eq 0
"

# A single-character process name must not produce a broken pattern.
SHORT="$(pattern_for 'ab')"
check "a two-character name still brackets correctly" test "${SHORT}" == 'a[b]'

finish "process_pattern (unit)"
