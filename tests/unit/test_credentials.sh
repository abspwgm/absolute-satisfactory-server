#!/bin/bash
# =============================================================================
# Unit Test: credential guard (no Docker, no network)
# A remote console behind an empty or well-known password is an open console.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$(dirname "${SCRIPT_DIR}")")"

source "${SCRIPT_DIR}/../test_helpers.sh"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

MANIFEST="${WORK_DIR}/manifest.env"

# Runs resolve_admin_credential with the given starting password.
# The resolved value lands in ${WORK_DIR}/resolved, the log in .../output.
resolve_with() {
    local password="$1"
    local var_name="${2:-ADMIN_PASSWORD}"
    (
        export TEST_ROOT="${WORK_DIR}/root"
        export MANIFEST_FILE="${MANIFEST}"
        mkdir -p "${TEST_ROOT}/config"
        export "${var_name}=${password}"
        source "${PROJECT_DIR}/scripts/common"
        resolve_admin_credential > "${WORK_DIR}/output" 2>&1
        printf '%s' "${!var_name}" > "${WORK_DIR}/resolved"
    )
}

password_file() { echo "${WORK_DIR}/root/config/admin_password"; }
resolved()      { cat "${WORK_DIR}/resolved"; }
file_password() { tr -d '\n' < "$(password_file)"; }
reset_state()   { rm -rf "${WORK_DIR}/root" "${WORK_DIR}/resolved" "${WORK_DIR}/output"; }

log_test_start "credentials (unit)"

write_manifest "${MANIFEST}" "ADMIN_PASSWORD_VAR=ADMIN_PASSWORD"

# --- every default is replaced ------------------------------------------------
for default in "" changeme password your_secure_password admin adminpassword rcon secret ChangeMe; do
    reset_state
    resolve_with "${default}"
    check "default '${default}': a password file is written" test -f "$(password_file)"
    check "default '${default}': it is mode 600" test "$(stat -c '%a' "$(password_file)" 2>/dev/null)" == "600"
    check "default '${default}': at least 24 characters" test "$(file_password | wc -c)" -ge 24
    check "default '${default}': the resolved value matches the file" test "$(resolved)" == "$(file_password)"
    check "default '${default}': it is not the default" test "$(resolved)" != "${default}"
    check "default '${default}': the value is never logged" bash -c "! grep -qF '$(resolved)' '${WORK_DIR}/output'"
    check "default '${default}': the log says where to read it" grep -q "admin_password" "${WORK_DIR}/output"
done

# --- an operator's own password is left alone --------------------------------
reset_state
resolve_with 'My-Own_S3cret'
check "a supplied password is used unchanged" test "$(resolved)" == 'My-Own_S3cret'
check "and no file is written" test ! -e "$(password_file)"

# --- a generated password is stable across restarts --------------------------
reset_state
resolve_with ""
FIRST="$(resolved)"
resolve_with ""
check "a generated password is reused on restart" test "$(resolved)" == "${FIRST}"

# --- a game with no console is skipped entirely ------------------------------
reset_state
write_manifest "${MANIFEST}" "ADMIN_PASSWORD_VAR="
resolve_with ""
check "no admin variable: nothing is generated" test ! -e "$(password_file)"

# --- the variable name comes from the manifest -------------------------------
reset_state
write_manifest "${MANIFEST}" "ADMIN_PASSWORD_VAR=RCON_PASSWORD"
resolve_with "" RCON_PASSWORD
check "the manifest names the file" test -f "${WORK_DIR}/root/config/rcon_password"
check "and the named variable is the one resolved" test "$(resolved | wc -c)" -ge 24

finish "credentials (unit)"
