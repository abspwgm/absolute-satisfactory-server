#!/bin/bash
# =============================================================================
# Unit Test: manifest validation (no Docker, no network)
# A server that starts with a guessed stop signal or a placeholder app id fails
# later, in a way that costs someone their world. It must fail here instead.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$(dirname "${SCRIPT_DIR}")")"

source "${SCRIPT_DIR}/../test_helpers.sh"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

# Loads a manifest with the given overrides in a clean subshell.
# Output lands in ${WORK_DIR}/output; the exit status is in LOAD_STATUS.
load_manifest() {
    local path="${WORK_DIR}/manifest.env"
    write_manifest "${path}" "$@"
    (
        MANIFEST_FILE="${path}"
        source "${PROJECT_DIR}/scripts/manifest"
        manifest_load
    ) > "${WORK_DIR}/output" 2>&1
    LOAD_STATUS=$?
}

loaded_ok()   { test "${LOAD_STATUS}" -eq 0; }
refused()     { test "${LOAD_STATUS}" -ne 0; }
said()        { grep -qi "$1" "${WORK_DIR}/output"; }

log_test_start "manifest (unit)"

# --- a complete manifest loads ------------------------------------------------
load_manifest
check "a complete manifest loads" loaded_ok

# --- every required value is required ----------------------------------------
for required in GAME_ID GAME_NAME STEAM_LOGIN STEAM_BRANCH STEAM_PLATFORM \
                SERVER_BINARY SERVER_PROCESS STOP_SIGNAL READY_LOG_PATTERN \
                PUBLIC_PORTS SAVE_PATHS SNAPSHOT_PATHS; do
    load_manifest "${required}="
    check "${required} is required" refused
done

# --- the placeholder app id must be replaced ---------------------------------
load_manifest "STEAM_APP_ID=0"
check "the placeholder app id is refused" refused
check "and it says why" said "placeholder"

load_manifest "STEAM_APP_ID=notanumber"
check "a non-numeric app id is refused" refused

# --- identifiers -------------------------------------------------------------
load_manifest "GAME_ID=Example_Server"
check "an uppercase or underscored GAME_ID is refused" refused
load_manifest "GAME_ID=7-days-to-die"
check "a hyphenated, lowercase GAME_ID is accepted" loaded_ok

# --- enumerations ------------------------------------------------------------
load_manifest "STEAM_LOGIN=maybe"
check "an unknown STEAM_LOGIN is refused" refused
load_manifest "STEAM_PLATFORM=macos"
check "an unsupported platform is refused" refused
load_manifest "STEAM_PLATFORM=windows"
check "the wine platform is accepted" loaded_ok
load_manifest "MOD_SOURCE=nexus"
check "an unsupported mod source is refused" refused
load_manifest "MOD_SOURCE=thunderstore"
check "a supported mod source is accepted" loaded_ok

# --- the stop signal is the one that costs saves -----------------------------
load_manifest "STOP_SIGNAL=KILL"
check "KILL is refused as a stop signal" refused
check "and it says what is allowed" said "INT or TERM"
load_manifest "STOP_SIGNAL=TERM"
check "TERM is accepted" loaded_ok

load_manifest "STOP_TIMEOUT=soon"
check "a non-numeric stop timeout is refused" refused

# --- ports -------------------------------------------------------------------
load_manifest "PUBLIC_PORTS=7777"
check "a port without a protocol is refused" refused
load_manifest "PUBLIC_PORTS=7777/sctp"
check "an unknown protocol is refused" refused
load_manifest "PUBLIC_PORTS=7777/udp,27015/tcp"
check "several ports are accepted" loaded_ok
load_manifest "PUBLIC_PORTS=27015-27016/udp"
check "a port range is accepted" loaded_ok
load_manifest "PRIVATE_PORTS=25575/tcp"
check "private ports are accepted" loaded_ok
load_manifest "PRIVATE_PORTS=25575"
check "a malformed private port is refused" refused

# --- a missing manifest is not an empty one ----------------------------------
LOAD_STATUS=0
(
    MANIFEST_FILE="${WORK_DIR}/absent.env"
    source "${PROJECT_DIR}/scripts/manifest"
    manifest_load
) > "${WORK_DIR}/output" 2>&1
LOAD_STATUS=$?
check "a missing manifest is refused" refused

finish "manifest (unit)"
