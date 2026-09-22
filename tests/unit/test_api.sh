#!/bin/bash
# =============================================================================
# Unit: the server API client, against a fake server
# =============================================================================
# The real API needs a running Satisfactory world, forty minutes of it. These
# checks are about the client: that an answer is parsed, that a refusal is a
# refusal, and - the one that matters most - that an unknown player count is
# never reported as zero. A guard that reads "nobody is on" from a server it
# cannot reach updates the game under the players standing in it (2.8).
#
# The fake speaks plain HTTP; the real one speaks TLS. API_URL exists for that.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../test_helpers.sh"

PROJECT_DIR="$(dirname "$(dirname "${SCRIPT_DIR}")")"
WORK_DIR="$(mktemp -d)"
trap 'stop_fake; rm -rf "${WORK_DIR}"' EXIT

MANIFEST="${WORK_DIR}/manifest.env"
write_manifest "${MANIFEST}"
mkdir -p "${WORK_DIR}/root/config"

# python3 on a runner, python on a Windows workstation. Each candidate is run
# rather than merely looked up: Windows ships a "python3" that exists only to
# advertise the Microsoft Store and exits non-zero. Without a working one there
# is no fake server to talk to, and the checks would test nothing.
PYTHON=""
for candidate in python3 python; do
    if command -v "${candidate}" >/dev/null 2>&1 && "${candidate}" -c 'pass' >/dev/null 2>&1; then
        PYTHON="${candidate}"
        break
    fi
done
if [[ -z "${PYTHON}" ]]; then
    log_warn "Skipped: no python to run the fake server with"
    exit 0
fi
# The client parses answers with jq, as it does in the image. A workstation
# without it would fail every check for a reason that has nothing to do with
# the code under test.
if ! command -v jq >/dev/null 2>&1; then
    log_warn "Skipped: jq is not installed here (the image has it)"
    exit 0
fi

FAKE_PID=""
FAKE_PORT=""
stop_fake() { [[ -n "${FAKE_PID}" ]] && kill "${FAKE_PID}" 2>/dev/null; FAKE_PID=""; }

# start_fake <players|none> ; a server that answers QueryServerState with that
# player count ("none" leaves the field out), PasswordLogin only for the right
# password, and SaveGame only with a bearer token. It records every request in
# ${WORK_DIR}/requests.log.
start_fake() {
    local players="$1"
    stop_fake
    FAKE_PORT="$("${PYTHON}" -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')"
    PLAYERS="${players}" REQUESTS="${WORK_DIR}/requests.log" "${PYTHON}" - "${FAKE_PORT}" <<'PY' &
import json, os, sys
from http.server import BaseHTTPRequestHandler, HTTPServer

PLAYERS = os.environ["PLAYERS"]
REQUESTS = os.environ["REQUESTS"]


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)) or 0)
        try:
            request = json.loads(body or b"{}")
        except ValueError:
            request = {}
        auth = self.headers.get("Authorization", "")
        with open(REQUESTS, "a", encoding="utf-8") as log:
            log.write(json.dumps({"request": request, "auth": auth}) + "\n")

        function = request.get("function")
        data = request.get("data") or {}
        if function == "QueryServerState":
            state = {"isGameRunning": True, "playerLimit": 4, "activeSessionName": "Fake"}
            if PLAYERS != "none":
                state["numConnectedPlayers"] = int(PLAYERS)
            return self.send(200, {"data": {"serverGameState": state}})
        if function == "PasswordLogin":
            if data.get("Password") == "right-password":
                return self.send(200, {"data": {"authenticationToken": "tok-123"}})
            return self.send(401, {"errorCode": "wrong_password"})
        if function == "SaveGame":
            if auth == "Bearer tok-123":
                return self.send(204, None)
            return self.send(403, {"errorCode": "insufficient_scope"})
        return self.send(404, {"errorCode": "unknown_function"})

    def send(self, code, payload):
        encoded = b"" if payload is None else json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        if encoded:
            self.wfile.write(encoded)


HTTPServer(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()
PY
    FAKE_PID=$!
    export API_URL="http://127.0.0.1:${FAKE_PORT}/api/v1"
    local waited=0
    until curl -s -m 2 -o /dev/null -X POST "${API_URL}" --data '{"function":"HealthCheck"}' 2>/dev/null; do
        sleep 0.2
        waited=$((waited + 1))
        [[ ${waited} -gt 50 ]] && { log_fail "The fake server never came up"; exit 1; }
    done
}

# Loads the client with the environment a container would have.
load_common() {
    export TEST_ROOT="${WORK_DIR}/root"
    export MANIFEST_FILE="${MANIFEST}"
    export ADMIN_PASSWORD="${1:-}"
    # shellcheck source=scripts/common
    source "${PROJECT_DIR}/scripts/common"
}

# --- a server with players on -------------------------------------------------
start_fake 2
( load_common "right-password"; [[ "$(get_player_count)" == "2" ]] ) \
    && log_pass "a live player count is read" || { log_fail "a live player count is read"; CHECKS_FAILED=$((CHECKS_FAILED + 1)); }

( load_common "right-password"; is_server_idle; [[ $? -eq 1 ]] ) \
    && log_pass "players on means not idle" || { log_fail "players on means not idle"; CHECKS_FAILED=$((CHECKS_FAILED + 1)); }

( load_common "right-password"; save_world e2e >/dev/null 2>&1 ) \
    && log_pass "a save is confirmed when the token is accepted" || { log_fail "a save is confirmed when the token is accepted"; CHECKS_FAILED=$((CHECKS_FAILED + 1)); }

( load_common ""; ! save_world e2e >/dev/null 2>&1 ) \
    && log_pass "no admin password means no save, rather than a silent one" || { log_fail "no admin password means no save, rather than a silent one"; CHECKS_FAILED=$((CHECKS_FAILED + 1)); }

( load_common "wrong-password"; ! admin_token >/dev/null 2>&1 ) \
    && log_pass "a refused login yields no token" || { log_fail "a refused login yields no token"; CHECKS_FAILED=$((CHECKS_FAILED + 1)); }

# --- a server nobody is on ----------------------------------------------------
start_fake 0
( load_common "right-password"; is_server_idle ) \
    && log_pass "an empty server is idle" || { log_fail "an empty server is idle"; CHECKS_FAILED=$((CHECKS_FAILED + 1)); }

# --- a server that will not say -----------------------------------------------
start_fake none
( load_common "right-password"; ! get_player_count >/dev/null 2>&1 ) \
    && log_pass "a missing count is not a count" || { log_fail "a missing count is not a count"; CHECKS_FAILED=$((CHECKS_FAILED + 1)); }

( load_common "right-password"; is_server_idle; [[ $? -eq 2 ]] ) \
    && log_pass "an unknown count is unknown (2), never idle (0)" || { log_fail "an unknown count is unknown (2), never idle (0)"; CHECKS_FAILED=$((CHECKS_FAILED + 1)); }

# --- an unreachable server ----------------------------------------------------
stop_fake
( load_common "right-password"; ! get_player_count >/dev/null 2>&1 ) \
    && log_pass "an unreachable server yields no count" || { log_fail "an unreachable server yields no count"; CHECKS_FAILED=$((CHECKS_FAILED + 1)); }

( load_common "right-password"; is_server_idle; [[ $? -eq 2 ]] ) \
    && log_pass "an unreachable server is unknown, not empty" || { log_fail "an unreachable server is unknown, not empty"; CHECKS_FAILED=$((CHECKS_FAILED + 1)); }

# --- the password never reaches a command line --------------------------------
# It is passed to curl in the request body, so it is not in /proc/<pid>/cmdline
# for anything on the host to read.
if grep -qE 'curl[^|]*(-u |--user)' "${PROJECT_DIR}/scripts/common"; then
    log_fail "the password travels in the request body, not as a curl argument"
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
else
    log_pass "the password travels in the request body, not as a curl argument"
fi

finish "api (unit)"
