#!/bin/bash
# =============================================================================
# Unit Test: pinned downloads (no Docker, no network)
# Anything fetched at run time that will execute is pinned and verified before
# a single file is used. An unpinned fetch is refused, not downgraded.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$(dirname "${SCRIPT_DIR}")")"

source "${SCRIPT_DIR}/../test_helpers.sh"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

MANIFEST="${WORK_DIR}/manifest.env"
write_manifest "${MANIFEST}"

ARTIFACT="${WORK_DIR}/release/pack.zip"
mkdir -p "$(dirname "${ARTIFACT}")"
printf 'pretend this is a mod loader\n' > "${ARTIFACT}"
GOOD_SHA="$(sha256sum "${ARTIFACT}" | cut -d' ' -f1)"
BAD_SHA="0000000000000000000000000000000000000000000000000000000000000000"

DESTINATION="${WORK_DIR}/download/pack.zip"

# Runs fetch_pinned against a local file:// "release".
fetch() {
    local url="$1"
    local sha="$2"
    rm -rf "${WORK_DIR}/download"
    (
        export TEST_ROOT="${WORK_DIR}/root"
        export MANIFEST_FILE="${MANIFEST}"
        source "${PROJECT_DIR}/scripts/common"
        fetch_pinned "${url}" "${sha}" "${DESTINATION}"
    ) > "${WORK_DIR}/output" 2>&1
    FETCH_STATUS=$?
}

fetched()     { test "${FETCH_STATUS}" -eq 0; }
refused()     { test "${FETCH_STATUS}" -ne 0; }
said()        { grep -qi "$1" "${WORK_DIR}/output"; }
on_disk()     { test -f "${DESTINATION}"; }
not_on_disk() { test ! -f "${DESTINATION}"; }

log_test_start "pinned_fetch (unit)"

# --- a matching checksum is accepted -----------------------------------------
fetch "file://${ARTIFACT}" "${GOOD_SHA}"
check "a matching checksum succeeds" fetched
check "and the file is kept" on_disk

# --- a tampered artifact is refused, and nothing is left behind --------------
fetch "file://${ARTIFACT}" "${BAD_SHA}"
check "a mismatched checksum fails" refused
check "the mismatch is reported" said "checksum mismatch"
check "the expected value is shown" said "expected"
check "nothing is left on disk" not_on_disk

# --- an unpinned fetch is refused before any download ------------------------
fetch "file://${ARTIFACT}" ""
check "an empty checksum fails" refused
check "it says the fetch is unpinned" said "unpinned"
check "nothing is downloaded" not_on_disk

fetch "" "${GOOD_SHA}"
check "an empty URL fails" refused
check "nothing is downloaded" not_on_disk

# --- an unreachable source fails, rather than succeeding with nothing --------
fetch "file://${WORK_DIR}/absent.zip" "${GOOD_SHA}"
check "an unreachable source fails" refused
check "nothing is left on disk" not_on_disk

finish "pinned_fetch (unit)"
