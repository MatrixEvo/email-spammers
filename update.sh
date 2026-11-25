#!/usr/bin/env bash

# Ultra-fast parallel deployer + runner + cron auditor for /ips1/blocklists/getnrd.sh
# across all 8 PMG nodes with a live, in-place updating status table.
#
# What it does on all 8 PMGs in parallel (single SSH trip per node):
#   1. Ensures /ips1/blocklists exists and atomically deploys getnrd.sh (chmod 755, bash -n)
#   2. Immediately runs /ips1/blocklists/getnrd.sh to pull all 6 blocklists from GitHub
#   3. Audits root crontab + /etc/cron* (read-only) and reports each node's active cron entry
#
# Usage:
#   ./update.sh
#   DRY_RUN=1 ./update.sh      # check remote state + cron without modifying anything
#   SKIP_RUN=1 ./update.sh     # deploy getnrd.sh without running it immediately
#   SSH_USER=root SSH_KEY=/path/to/key ./update.sh

set -uo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOCAL_FILE="${LOCAL_FILE:-${SCRIPT_DIR}/getnrd.sh}"
readonly REMOTE_DIR="${REMOTE_DIR:-/ips1/blocklists}"
readonly REMOTE_FILE="${REMOTE_DIR}/getnrd.sh"
readonly SSH_USER="${SSH_USER:-root}"
readonly SSH_KEY="${SSH_KEY:-/mnt/c/Users/8067-C1908/Documents/secure/Nicholas.keynew}"
readonly CONNECT_TIMEOUT="${CONNECT_TIMEOUT:-5}"
readonly DRY_RUN="${DRY_RUN:-0}"
readonly SKIP_RUN="${SKIP_RUN:-0}"

readonly -a TARGETS=(
    "103.21.180.46:9321"
    "103.21.180.36:22"
    "103.21.180.184:9321"
    "103.21.180.47:9321"
    "103.21.180.189:9321"
    "103.21.180.165:9321"
    "103.21.180.143:9321"
    "43.228.247.170:22"
)

exec 200>"/tmp/pmg_blocklist_update.lock"
if ! flock -n 200; then
    echo "Another instance of blocklist/update.sh is already running. Exiting." >&2
    exit 1
fi

IS_TTY=0
[[ -t 1 ]] && IS_TTY=1

STAGED_KEY=""
STAGED_SRC=""
STATE_DIR="$(mktemp -d /tmp/pmg_bl_upd_state.XXXXXX)"
RENDER_LOCK="${STATE_DIR}/render.lock"

cleanup() {
    [[ ${IS_TTY} -eq 1 ]] && printf '\033[?25h'
    [[ -n "${STAGED_KEY}" && -f "${STAGED_KEY}" ]] && rm -f "${STAGED_KEY}"
    [[ -n "${STAGED_SRC}" && -f "${STAGED_SRC}" ]] && rm -f "${STAGED_SRC}"
    [[ -n "${STATE_DIR}" && -d "${STATE_DIR}" ]] && rm -rf "${STATE_DIR}"
}
trap cleanup EXIT

prepare_source() {
    if [[ ! -f "${LOCAL_FILE}" || ! -s "${LOCAL_FILE}" ]]; then
        echo "ERROR: Source script not found or empty: ${LOCAL_FILE}" >&2
        exit 1
    fi

    STAGED_SRC="$(mktemp /tmp/pmg_getnrd_src.XXXXXX)"
    chmod 644 "${STAGED_SRC}"
    tr -d '\r' < "${LOCAL_FILE}" > "${STAGED_SRC}"

    local syn_err
    if ! syn_err="$(bash -n "${STAGED_SRC}" 2>&1)"; then
        echo "ERROR: Local bash syntax check failed for ${LOCAL_FILE}:" >&2
        echo "${syn_err}" >&2
        exit 1
    fi

    LOCAL_SHA="$(sha256sum "${STAGED_SRC}" | awk '{print $1}')"
}

prepare_ssh_key() {
    [[ -z "${SSH_KEY}" ]] && return 0
    if [[ ! -f "${SSH_KEY}" ]]; then
        echo "ERROR: SSH_KEY not found: ${SSH_KEY}" >&2
        exit 1
    fi
    local first_line
    first_line="$(head -n 1 "${SSH_KEY}" | tr -d '\r')"
    if [[ "${first_line}" == PuTTY-User-Key-File* ]]; then
        echo "ERROR: ${SSH_KEY} is in PuTTY (.ppk) format. Use an OpenSSH private key." >&2
        exit 1
    fi
    STAGED_KEY="$(mktemp /tmp/pmg_bl_key.XXXXXX)"
    chmod 600 "${STAGED_KEY}"
    tr -d '\r' < "${SSH_KEY}" > "${STAGED_KEY}"
}

prepare_source
prepare_ssh_key

if [[ ${IS_TTY} -eq 1 ]]; then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_DIM=$'\033[2m'
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_RED=$'\033[31m'
    C_CYAN=$'\033[36m'
    C_EOL=$'\033[K'
else
    C_RESET="" C_BOLD="" C_DIM="" C_GREEN="" C_YELLOW="" C_RED="" C_CYAN="" C_EOL=""
fi

num_targets="${#TARGETS[@]}"
TABLE_LINES=$((num_targets + 5))

write_row_state() {
    local idx="$1" host="$2" st="$3" sync_info="$4" cron_info="$5"
    local tmp="${STATE_DIR}/row_${idx}.tmp.$$"
    printf '%s|%s|%s|%s\n' "${host}" "${st}" "${sync_info}" "${cron_info}" > "${tmp}"
    mv -f "${tmp}" "${STATE_DIR}/row_${idx}"
}

for ((i = 0; i < num_targets; i++)); do
    write_row_state "${i}" "-" "CONNECTING" "-" "probing..."
done

color_for_state() {
    case "$1" in
        OK)                   printf '%s' "${C_GREEN}" ;;
        DRY-RUN|WARN)         printf '%s' "${C_YELLOW}" ;;
        FAIL)                 printf '%s' "${C_RED}" ;;
        CONNECTING*|SYNCING*) printf '%s' "${C_CYAN}" ;;
        *)                    printf '%s' "${C_DIM}" ;;
    esac
}

render_table() {
    local move_up="${1:-1}"
    if [[ ${IS_TTY} -eq 1 && ${move_up} -eq 1 ]]; then
        printf '\033[%dA' "${TABLE_LINES}"
    fi

    local mode_tag=" [PARALLEL]"
    [[ ${DRY_RUN} -eq 1 ]] && mode_tag+=" [DRY-RUN]"
    [[ ${SKIP_RUN} -eq 1 ]] && mode_tag+=" [SKIP-RUN]"

    printf '%s%sPMG Blocklist Sync Deploy%s%s -> %s\n' \
        "${C_EOL}" "${C_BOLD}" "${C_RESET}" "${mode_tag}" "${REMOTE_FILE}"
    printf '%sSource: %s (sha256:%s) | Checks crontab + /etc/cron* (read-only)\n' \
        "${C_EOL}" "$(basename "${LOCAL_FILE}")" "${LOCAL_SHA:0:12}"
    printf '%s\n' "${C_EOL}"
    printf '%s%s%-22s %-18s %-10s %-20s %s%s\n' \
        "${C_EOL}" "${C_BOLD}" "TARGET" "HOST" "STATUS" "SYNC RESULT" "CRON ENTRY" "${C_RESET}"
    printf '%s------------------------------------------------------------------------------------------------------\n' "${C_EOL}"

    local idx host st sync_info cron_info col
    for ((idx = 0; idx < num_targets; idx++)); do
        IFS='|' read -r host st sync_info cron_info < "${STATE_DIR}/row_${idx}"
        col="$(color_for_state "${st}")"
        printf '%s%-22s %-18s %s%-10s%s %-20s %s\n' \
            "${C_EOL}" \
            "${TARGETS[idx]}" \
            "${host:0:18}" \
            "${col}" "${st}" "${C_RESET}" \
            "${sync_info:0:20}" \
            "${cron_info:0:46}"
    done
}

locked_render() {
    [[ ${IS_TTY} -eq 1 ]] || return 0
    (
        flock 9
        render_table 1
    ) 9>"${RENDER_LOCK}"
}

process_target() {
    local idx="$1"
    local target="${TARGETS[idx]}"
    local ip="${target%%:*}"
    local port="${target##*:}"

    local -a ssh_opts=(
        -p "${port}"
        -o "ConnectTimeout=${CONNECT_TIMEOUT}"
        -o "StrictHostKeyChecking=accept-new"
        -o "PubkeyAcceptedAlgorithms=+ssh-rsa"
        -o "BatchMode=yes"
    )
    [[ -n "${STAGED_KEY}" ]] && ssh_opts+=(-i "${STAGED_KEY}" -o "IdentitiesOnly=yes")

    local remote_tmp="${REMOTE_DIR}/.getnrd.sh.tmp.$$_${idx}"
    local remote_cmd out rc=0
    remote_cmd="set -uo pipefail
h=\$(hostname -s 2>/dev/null || hostname </dev/null)
echo \"__HOST__\${h}\"

# 1. Read-only cron audit across root crontab and /etc/cron*
cron_hits=\$({
    crontab -l 2>/dev/null | grep -v '^[[:space:]]*#' | grep -E 'getnrd|blocklist|get\.sh' || true
    grep -rnhsE 'getnrd|blocklist|get\.sh' /etc/crontab /etc/cron.d /etc/cron.hourly /etc/cron.daily 2>/dev/null | grep -v ':.*#' || true
} | head -n 3 | tr '\n' ';' | sed 's/;$//')
echo \"__CRON__\${cron_hits:-NONE}\"

if [[ '${DRY_RUN}' -eq 1 ]]; then
    if [[ -f '${REMOTE_FILE}' ]]; then
        rsha=\$(sha256sum '${REMOTE_FILE}' </dev/null | awk '{print \$1}')
    else
        rsha='MISSING'
    fi
    cnt=0
    for f in gmail_spammers.txt spammers.txt ip_blocklist.txt spf_softfail_strict.txt backscatter_protection.txt url_blocklist.txt; do
        [[ -s '${REMOTE_DIR}/'\"\$f\" ]] && cnt=\$((cnt + 1))
    done
    echo \"__DRY__\${rsha:0:8}|\${cnt}/6 lists\"
    exit 0
fi

# 2. Deploy getnrd.sh atomically
mkdir -p '${REMOTE_DIR}'
tmp='${remote_tmp}'
cat > \"\${tmp}\"
got=\$(sha256sum \"\${tmp}\" | awk '{print \$1}')
if [[ \"\${got}\" != '${LOCAL_SHA}' ]]; then
    rm -f \"\${tmp}\"
    echo '__ERR__sha256 mismatch after upload'
    exit 2
fi
if ! bash -n \"\${tmp}\" 2>/dev/null; then
    rm -f \"\${tmp}\"
    echo '__ERR__remote bash -n failed'
    exit 3
fi
chmod 755 \"\${tmp}\"
mv -f \"\${tmp}\" '${REMOTE_FILE}'

# 3. Run getnrd.sh immediately unless SKIP_RUN=1
if [[ '${SKIP_RUN}' -eq 1 ]]; then
    echo '__SYNC__deployed (skip-run)'
    exit 0
fi

run_out=\$('${REMOTE_FILE}' 2>&1)
run_rc=\$?
summary=\$(grep '^Summary:' <<< \"\${run_out}\" | sed 's/^Summary: //; s/ (dir:.*//' || true)
if [[ \${run_rc} -eq 0 ]]; then
    echo \"__SYNC__\${summary:-6 updated}\"
else
    err_l=\$(grep '^Error:' <<< \"\${run_out}\" | head -n 1 | tr '|' '/' || echo \"exit \${run_rc}\")
    echo \"__ERR__\${err_l}\"
    exit 4
fi"

    if [[ ${DRY_RUN} -eq 1 ]]; then
        out="$(ssh "${ssh_opts[@]}" "${SSH_USER}@${ip}" "${remote_cmd}" </dev/null 2>&1)" || rc=$?
    else
        out="$(ssh "${ssh_opts[@]}" "${SSH_USER}@${ip}" "${remote_cmd}" < "${STAGED_SRC}" 2>&1)" || rc=$?
    fi

    local remote_host cron_raw sync_msg dry_msg err_msg cron_disp
    remote_host="$(sed -n 's/^__HOST__//p' <<< "${out}" | head -n 1 | tr -d '\r')"
    [[ -z "${remote_host}" ]] && remote_host="-"
    cron_raw="$(sed -n 's/^__CRON__//p' <<< "${out}" | head -n 1 | tr -d '\r' | tr '|' '/')"
    sync_msg="$(sed -n 's/^__SYNC__//p' <<< "${out}" | head -n 1 | tr -d '\r' | tr '|' '/')"
    dry_msg="$(sed -n 's/^__DRY__//p' <<< "${out}" | head -n 1 | tr -d '\r' | tr '|' '/')"
    err_msg="$(sed -n 's/^__ERR__//p' <<< "${out}" | head -n 1 | tr -d '\r' | tr '|' '/')"

    printf '%s\t%s\t%s\n' "${target}" "${remote_host}" "${cron_raw:-UNKNOWN}" > "${STATE_DIR}/cron_${idx}"

    if [[ -z "${cron_raw}" || "${cron_raw}" == "NONE" ]]; then
        cron_disp="MISSING CRON!"
    else
        cron_disp="${cron_raw}"
    fi

    if [[ ${rc} -ne 0 ]]; then
        if [[ -z "${err_msg}" ]]; then
            err_msg="$(grep -v '^__' <<< "${out}" | grep -v '^[[:space:]]*$' | tail -n 1 | tr -d '\r' | tr '|' '/')"
        fi
        write_row_state "${idx}" "${remote_host}" "FAIL" "${err_msg:-ssh exit ${rc}}" "${cron_disp}"
        locked_render
        return 1
    fi

    if [[ ${DRY_RUN} -eq 1 ]]; then
        write_row_state "${idx}" "${remote_host}" "DRY-RUN" "${dry_msg}" "${cron_disp}"
        locked_render
        return 0
    fi

    if [[ "${cron_disp}" == "MISSING CRON!" ]]; then
        write_row_state "${idx}" "${remote_host}" "WARN" "${sync_msg}" "${cron_disp}"
    else
        write_row_state "${idx}" "${remote_host}" "OK" "${sync_msg}" "${cron_disp}"
    fi
    locked_render
    return 0
}

[[ ${IS_TTY} -eq 1 ]] && printf '\033[?25l'
[[ ${IS_TTY} -eq 1 ]] && render_table 0

pids=()
for ((i = 0; i < num_targets; i++)); do
    process_target "${i}" &
    pids+=("$!")
done

for pid in "${pids[@]}"; do
    wait "${pid}" || true
done

render_table "${IS_TTY}"

ok=0 warn=0 fail=0
for ((i = 0; i < num_targets; i++)); do
    IFS='|' read -r _ st _ _ < "${STATE_DIR}/row_${i}"
    case "${st}" in
        OK|DRY-RUN) ok=$((ok + 1)) ;;
        WARN)       warn=$((warn + 1)) ;;
        *)          fail=$((fail + 1)) ;;
    esac
done

printf '\nDone: %d OK, %d missing-cron warning(s), %d failed\n' "${ok}" "${warn}" "${fail}"

# Print full untruncated cron audit lines below table so nothing gets cut off
printf '\nCron Audit Details:\n'
for ((i = 0; i < num_targets; i++)); do
    if [[ -f "${STATE_DIR}/cron_${i}" ]]; then
        IFS=$'\t' read -r tgt hst crn < "${STATE_DIR}/cron_${i}"
        printf '  %-20s %-16s %s\n' "${tgt}" "(${hst})" "${crn}"
    fi
done

[[ ${fail} -eq 0 ]]
