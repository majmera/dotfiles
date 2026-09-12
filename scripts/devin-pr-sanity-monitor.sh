#!/usr/bin/env bash
set -euo pipefail

PR_URL="https://eos2git.cec.lab.emc.com/cyclone/cyclone/pull/135907"
PR_ID="135907"
STATE_DIR="${HOME}/.local/state/devin-pr-monitor"
LOCK_DIR="/tmp/devin-pr-sanity-monitor.lock"
LOG_FILE="${STATE_DIR}/cron.log"
STAMP_FILE="${STATE_DIR}/last-rerun.txt"
DRY_RUN="${DEVIN_PR_MONITOR_DRY_RUN:-0}"
GH_BIN="/usr/bin/gh"
CRON_ENTRY="0 * * * * /home/cyc/bin/devin-pr-sanity-monitor.sh"

mkdir -p "${STATE_DIR}"

if [[ -z "${GITHUB_ENTERPRISE_TOKEN:-}" ]] && command -v pass >/dev/null 2>&1; then
    set +e
    GITHUB_ENTERPRISE_TOKEN="$(pass show gh/pat 2>/dev/null)"
    STATUS=$?
    set -e

    if [[ ${STATUS} -eq 0 && -n "${GITHUB_ENTERPRISE_TOKEN}" ]]; then
        export GITHUB_ENTERPRISE_TOKEN
        export GH_HOST="${GH_HOST:-eos2git.cec.lab.emc.com}"
        unset GITHUB_TOKEN GH_TOKEN
    fi
fi

log() {
    printf '%s %s\n' "$(date -Is)" "$*" >> "${LOG_FILE}"
}

notify() {
    local msg="$1"

    if command -v notify-send >/dev/null 2>&1; then
        notify-send "PR monitor" "${msg}" || true
    fi
}

fail() {
    log "$1"
    notify "$2"
    exit 1
}

disable_cron() {
    local tmp
    tmp=$(mktemp)

    if ! (crontab -l 2>/dev/null || true) | python3 -c 'import sys; entry = sys.argv[1]; lines = [line.rstrip("\n") for line in sys.stdin]; kept = [line for line in lines if line != entry and line.strip()]; sys.stdout.write("\n".join(kept) + ("\n" if kept else ""))' "${CRON_ENTRY}" > "${tmp}"; then
        rm -f "${tmp}"
        return 1
    fi

    crontab "${tmp}"
    rm -f "${tmp}"
}

if [[ ! -x "${GH_BIN}" ]]; then
    fail "gh binary not found at ${GH_BIN}" "PR monitor failed: gh was not found at ${GH_BIN}"
fi

if ! mkdir "${LOCK_DIR}" 2>/dev/null; then
    log "another run is already in progress"
    exit 0
fi
trap 'rmdir "${LOCK_DIR}"' EXIT

log "starting check for ${PR_URL}"

set +e
PR_SANITY_STATE="$(${GH_BIN} pr view "${PR_URL}" --json statusCheckRollup --jq '[.statusCheckRollup[] | select(.name == "PR_Sanity")][0] | if . == null then "MISSING" else (.status + "|" + (.conclusion // "")) end' 2>&1)"
STATUS=$?
set -e

printf '%s\n' "${PR_SANITY_STATE}" >> "${LOG_FILE}"

if [[ ${STATUS} -ne 0 ]]; then
    log "gh pr view failed with exit ${STATUS}: ${PR_SANITY_STATE}"
    fail "failed to fetch PR status with gh (exit ${STATUS})" "PR monitor failed to read PR ${PR_ID} status"
fi

case "${PR_SANITY_STATE}" in
    COMPLETED\|FAILURE)
        if [[ "${DRY_RUN}" == "1" ]]; then
            log "dry-run: would post 'retry sanity'"
            exit 0
        fi

        if ! COMMENT_OUTPUT="$(${GH_BIN} pr comment "${PR_URL}" --body "retry sanity" 2>&1)"; then
            printf '%s\n' "${COMMENT_OUTPUT}" >> "${LOG_FILE}"
            log "gh pr comment failed: ${COMMENT_OUTPUT}"
            fail "failed to post retry sanity comment" "PR monitor failed to rerun PR_Sanity for PR ${PR_ID}"
        fi

        TS="$(date -Is)"
        printf '%s\n' "${TS}" > "${STAMP_FILE}"
        printf '%s\n' "${COMMENT_OUTPUT}" >> "${LOG_FILE}"
        log "PR_Sanity failed; posted 'retry sanity'"
        notify "PR_Sanity rerun triggered for PR ${PR_ID} at ${TS}"
        ;;
    COMPLETED\|SUCCESS)
        if [[ "${DRY_RUN}" == "1" ]]; then
            log "dry-run: would remove cron entry after PR_Sanity success"
            exit 0
        fi

        if ! disable_cron; then
            fail "failed to remove cron entry after PR_Sanity success" "PR monitor could not disable its cron job for PR ${PR_ID}"
        fi

        log "PR_Sanity passed; removed cron entry"
        notify "PR_Sanity passed for PR ${PR_ID}; cron job disabled"
        ;;
    MISSING)
        fail "PR_Sanity check was not present on the PR" "PR monitor could not find PR_Sanity on PR ${PR_ID}"
        ;;
    *)
        log "no action needed: PR_Sanity state is ${PR_SANITY_STATE}"
        ;;
esac
