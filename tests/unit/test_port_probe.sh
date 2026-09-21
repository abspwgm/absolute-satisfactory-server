#!/bin/bash
# =============================================================================
# Unit Test: udp_port_bound (no Docker, no game)
# The port probe used `ss`, which no image in this family installs. Guarded by
# `command -v ss` in the healthcheck it silently never ran; unguarded in the e2e
# suite it could never succeed. This binds real sockets and reads them back the
# way the healthcheck now does, from /proc/net.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$(dirname "${SCRIPT_DIR}")")"

source "${SCRIPT_DIR}/../test_helpers.sh"

WORK_DIR="$(mktemp -d)"
HOLDERS=()
cleanup() {
    local pid
    for pid in "${HOLDERS[@]}"; do kill "${pid}" 2>/dev/null; done
    rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

probe() {
    (
        export TEST_ROOT="${WORK_DIR}/root"
        export MANIFEST_FILE="${PROJECT_DIR}/manifest.env"
        source "${PROJECT_DIR}/scripts/common"
        udp_port_bound "$1"
    ) 2>/dev/null
}

# hold <family: 4|6> <proto: udp|tcp> ; binds a free port, keeps it open, and
# leaves the number in HELD_PORT. Not called via $( ): the holder would inherit
# that pipe and block it, and HOLDERS would never reach this shell to be cleaned.
hold() {
    local out="${WORK_DIR}/port.${RANDOM}${RANDOM}"
    HELD_PORT=""
    python3 - "$1" "$2" "${out}" > /dev/null 2>&1 <<'PY' &
import os, socket, sys, time
family = socket.AF_INET6 if sys.argv[1] == "6" else socket.AF_INET
kind = socket.SOCK_DGRAM if sys.argv[2] == "udp" else socket.SOCK_STREAM
s = socket.socket(family, kind)
s.bind(("::1" if family == socket.AF_INET6 else "127.0.0.1", 0))
if kind == socket.SOCK_STREAM:
    s.listen()
with open(sys.argv[3] + ".tmp", "w") as f:
    f.write(str(s.getsockname()[1]))
os.replace(sys.argv[3] + ".tmp", sys.argv[3])
time.sleep(60)
PY
    HOLDERS+=("$!")
    local tries=0
    until [[ -s "${out}" ]]; do
        [[ ${tries} -ge 50 ]] && return 1
        sleep 0.1
        tries=$((tries + 1))
    done
    HELD_PORT="$(cat "${out}")"
}

log_test_start "port_probe (unit)"

hold 4 udp
check "a bound IPv4 UDP port is seen" probe "${HELD_PORT}"

if [[ -r /proc/net/udp6 ]] && hold 6 udp && [[ -n "${HELD_PORT}" ]]; then
    check "a bound IPv6 UDP port is seen" probe "${HELD_PORT}"
else
    log_warn "IPv6 unavailable here; skipping the udp6 case"
fi

# The game port is UDP. A TCP listener on the same number is not the game.
hold 4 tcp
PROBE_TCP_RESULT=0
probe "${HELD_PORT}" || PROBE_TCP_RESULT=1
check "a TCP-only port does not count as the UDP game port" test "${PROBE_TCP_RESULT}" -eq 1

# A port nobody holds. Take one from the kernel and release it.
FREE="$(python3 -c 'import socket; s=socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')"
PROBE_FREE_RESULT=0
probe "${FREE}" || PROBE_FREE_RESULT=1
check "an unbound port is reported as unbound" test "${PROBE_FREE_RESULT}" -eq 1

# Low ports have leading zeros in the table (":0035" for 53); the hex must be
# padded the same way or a short port could match the tail of a longer one.
check "the port is matched as four padded hex digits" \
    bash -c "grep -q \"printf '%04X'\" '${PROJECT_DIR}/scripts/common'"

check "the healthcheck no longer depends on ss" \
    bash -c "! grep -qE '(^|[^a-z])ss -l' '${PROJECT_DIR}/scripts/healthcheck'"

finish "port_probe (unit)"
