#!/bin/bash
# =============================================================================
# End-to-end suite: build, start, climb the ready ladder, tear down.
# =============================================================================
# Standard 2.10 defines ready as a ladder: up, reachable, discoverable, an
# authenticated session, recoverable. A rung passes only when every test that
# proves it ran and passed, and the verdict is the highest rung reached with
# every rung below it passed too. verdict.json is what the fleet board reads,
# and it never claims more than was proven.
#
# Order is not the ladder. authenticated runs before discoverable because a
# fresh Satisfactory server has no admin and no world: claiming it and creating
# the session is what makes there be anything to discover. The rungs are scored
# from the results, not from the order they were run in.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"
source "${SCRIPT_DIR}/test_helpers.sh"

COMPOSE="docker compose -f ${PROJECT_DIR}/docker-compose.test.yml"
CONTAINER="satisfactory-server"
LOGS_DIR="${PROJECT_DIR}/data/logs"
VERDICT_FILE="${LOGS_DIR}/verdict.json"

# graceful_shutdown stops the container and restart_update starts it again, so
# they are last and in that order.
TESTS=(server_start server_query authenticated discoverable backup graceful_shutdown restart_update)
declare -A TEST_RESULT=()
FAILED=()

# -----------------------------------------------------------------------------
# The ready ladder (standard 2.10)
# -----------------------------------------------------------------------------
LADDER=(up reachable discoverable authenticated recoverable)
declare -A RUNG_TESTS=(
    [up]="server_start"
    [reachable]="server_query"
    [discoverable]="discoverable"
    [authenticated]="authenticated"
    [recoverable]="backup graceful_shutdown restart_update"
)
# Satisfactory has no server browser: a player adds a server by address and the
# client asks it what it is. Answering that is the whole of "discoverable"
# here, so the rung is the client's own question, not a listing somewhere.
DISCOVERABLE_MEANS="the server answers a client that asks what it is (QueryServerState); Satisfactory has no server browser to be listed in"
# The admin session is real - the same token the game's client gets - but no
# headless Satisfactory client exists, so nobody joins the world in CI.
AUTHENTICATED_STAND_IN="an administrator session on the server's own API (claim, login, create world); not a player join"

cleanup() {
    log_info "Tearing down"
    ${COMPOSE} down -v >/dev/null 2>&1 || true
}
trap cleanup EXIT

# What the run needs from its environment rather than from the image. When one
# is missing the run is inconclusive, not failed (2.11), and exits 3: a runner
# that cannot build or reach Steam says nothing about whether the server works.
check_preconditions() {
    if ! docker info >/dev/null 2>&1; then
        echo "the Docker daemon is not reachable"
        return 1
    fi
    if command -v curl >/dev/null 2>&1 \
        && ! curl -sf -m 20 -o /dev/null https://api.steampowered.com/ISteamWebAPIUtil/GetServerInfo/v1/; then
        echo "Steam's web API is unreachable from the runner"
        return 1
    fi
    local free_kb
    free_kb="$(df -Pk "${PROJECT_DIR}" | awk 'NR == 2 {print $4}')"
    if [[ "${free_kb}" =~ ^[0-9]+$ ]] && (( free_kb < 20 * 1024 * 1024 )); then
        echo "the runner has under 20 GB free for the install, the world and its backups"
        return 1
    fi
    return 0
}

rung_status() {
    local test status="pass"
    [[ -z "${RUNG_TESTS[$1]:-}" ]] && { echo "not_applicable"; return; }
    for test in ${RUNG_TESTS[$1]}; do
        case "${TEST_RESULT[${test}]:-not_run}" in
            pass) ;;
            fail) echo "fail"; return ;;
            *) status="not_run" ;;
        esac
    done
    echo "${status}"
}

# write_verdict <verdict> [reason] ; verdict.json, plus a job summary in CI.
# Written before the teardown: it reads the Steam build from the container.
write_verdict() {
    local verdict="$1" reason="${2:-}" reached="null" rung status rungs="" build
    for rung in "${LADDER[@]}"; do
        rungs+="${rungs:+, }\"${rung}\": \"$(rung_status "${rung}")\""
    done
    if [[ "${verdict}" != "inconclusive" ]]; then
        for rung in "${LADDER[@]}"; do
            status="$(rung_status "${rung}")"
            [[ "${status}" == "not_applicable" ]] && continue
            [[ "${status}" == "pass" ]] || break
            reached="\"${rung}\""
        done
    fi
    build="$(MSYS_NO_PATHCONV=1 docker exec "${CONTAINER}" sed -n 's/.*"buildid"[[:space:]]*"\([0-9]*\)".*/\1/p' \
        "/opt/satisfactory/server/steamapps/appmanifest_${STEAM_APP_ID:-1690800}.acf" 2>/dev/null | head -1)" || true
    local build_json="null"
    [[ "${build}" =~ ^[0-9]+$ ]] && build_json="\"${build}\""
    reason="${reason//\\/\\\\}"
    reason="${reason//\"/\\\"}"
    mkdir -p "${LOGS_DIR}"
    cat > "${VERDICT_FILE}" <<EOF
{
  "schema": 1,
  "game": "satisfactory",
  "verdict": "${verdict}",
  "reason": "${reason}",
  "reached": ${reached},
  "rungs": {${rungs}},
  "stand_ins": {"authenticated": "${AUTHENTICATED_STAND_IN}", "discoverable": "${DISCOVERABLE_MEANS}"},
  "steam_build": ${build_json},
  "commit": "${GITHUB_SHA:-$(git -C "${PROJECT_DIR}" rev-parse HEAD 2>/dev/null)}",
  "event": "${GITHUB_EVENT_NAME:-local}",
  "finished_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    log_info "Verdict: ${verdict}${reason:+ (${reason})}; reached ${reached//\"/}; build ${build:-unknown}"
    if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
        {
            echo "### Ready ladder: **${verdict}**${reason:+ — ${reason}}"
            echo ""
            echo "| Rung | Result |"
            echo "|---|---|"
            for rung in "${LADDER[@]}"; do
                echo "| ${rung} | $(rung_status "${rung}") |"
            done
            echo ""
            echo "Steam build: ${build:-unknown}."
            echo "Discoverable: ${DISCOVERABLE_MEANS}."
            echo "Authenticated: ${AUTHENTICATED_STAND_IN}."
        } >> "${GITHUB_STEP_SUMMARY}"
    fi
}

# Ready means every applicable rung passed: one that failed, or never ran, is
# not proven.
ladder_verdict() {
    local verdict="ready" rung status
    for rung in "${LADDER[@]}"; do
        status="$(rung_status "${rung}")"
        [[ "${status}" == "pass" || "${status}" == "not_applicable" ]] || verdict="degraded"
    done
    [[ "$(rung_status up)" == "pass" ]] || verdict="down"
    echo "${verdict}"
}

cd "${PROJECT_DIR}"
mkdir -p data/server data/config data/logs

missing=""
if ! missing="$(check_preconditions)"; then
    log_warn "Inconclusive before starting: ${missing}"
    write_verdict "inconclusive" "${missing}"
    exit 3
fi

log_info "Starting the stack"
if ! ${COMPOSE} up -d; then
    log_warn "Inconclusive: the stack would not start on this runner"
    write_verdict "inconclusive" "the test stack would not start"
    exit 3
fi

for name in "${TESTS[@]}"; do
    script="${SCRIPT_DIR}/e2e/test_${name}.sh"
    if [[ ! -f "${script}" ]]; then
        # Silence used to count as success here: a typo'd name was warned about
        # and the run still passed. A test that does not exist proves nothing.
        log_fail "No such test: ${name}"
        TEST_RESULT["${name}"]="fail"
        FAILED+=("${name}")
        continue
    fi
    log_info "=== ${name} ==="
    if bash "${script}"; then
        log_pass "${name}"
        TEST_RESULT["${name}"]="pass"
    else
        log_fail "${name}"
        TEST_RESULT["${name}"]="fail"
        FAILED+=("${name}")
        mkdir -p data/logs
        docker logs "${CONTAINER}" > "data/logs/${name}_FAILED.log" 2>&1 || true
    fi
done

write_verdict "$(ladder_verdict)"

echo ""
if [[ ${#FAILED[@]} -gt 0 ]]; then
    log_fail "Failed: ${#FAILED[@]} (${FAILED[*]})"
    exit 1
fi
log_pass "Every test passed"
exit 0
