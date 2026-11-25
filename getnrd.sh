#!/usr/bin/env bash

# Atomically sync all 6 PMG blocklists from MatrixEvo/email-spammers into DEST_DIR.
# Auto-detects DEST_DIR from this script's own directory (e.g. /ips1/blocklists on PMG),
# stages downloads in DEST_DIR/.<file>.tmp.$$ for same-filesystem atomic mv -f,
# busts GitHub CDN cache, and exits non-zero if any file fails.

set -uo pipefail

readonly DEST_DIR="${DEST_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
readonly BASE_URL="${BASE_URL:-https://raw.githubusercontent.com/MatrixEvo/email-spammers/refs/heads/main}"
readonly CACHE_BUST="$(date +%s)"

readonly -a FILES=(
    "gmail_spammers.txt"
    "spammers.txt"
    "ip_blocklist.txt"
    "spf_softfail_strict.txt"
    "backscatter_protection.txt"
    "url_blocklist.txt"
)

exec 200>"/tmp/pmg_getnrd.lock"
if ! flock -n 200; then
    echo "Another instance of getnrd.sh is already running. Exiting." >&2
    exit 1
fi

if ! mkdir -p "${DEST_DIR}"; then
    echo "Error: Destination directory does not exist and could not be created: ${DEST_DIR}" >&2
    exit 1
fi

ok=0
fail=0

update_blocklist() {
    local filename="$1"
    local url="${BASE_URL}/${filename}?t=${CACHE_BUST}"
    local tmp_file="${DEST_DIR}/.${filename}.tmp.$$"
    local dest_file="${DEST_DIR}/${filename}"

    if ! wget --timeout=15 --tries=2 --no-cache -q "${url}" -O "${tmp_file}"; then
        echo "Error: Could not download ${filename}." >&2
        rm -f "${tmp_file}"
        fail=$((fail + 1))
        return 1
    fi

    if [[ ! -s "${tmp_file}" ]]; then
        echo "Error: Downloaded ${filename} is empty; keeping existing file." >&2
        rm -f "${tmp_file}"
        fail=$((fail + 1))
        return 1
    fi

    if head -n 5 "${tmp_file}" | grep -qiE '^[[:space:]]*(<!DOCTYPE html|<html)'; then
        echo "Error: Downloaded ${filename} looks like an HTML error page; keeping existing file." >&2
        rm -f "${tmp_file}"
        fail=$((fail + 1))
        return 1
    fi

    sed -i 's/\r$//' "${tmp_file}"
    chmod 644 "${tmp_file}"

    if mv -f "${tmp_file}" "${dest_file}"; then
        echo "Success: Updated ${dest_file}."
        ok=$((ok + 1))
        return 0
    else
        echo "Error: Failed to move ${tmp_file} -> ${dest_file}." >&2
        rm -f "${tmp_file}"
        fail=$((fail + 1))
        return 1
    fi
}

for f in "${FILES[@]}"; do
    update_blocklist "${f}" || true
done

echo "Summary: ${ok} updated, ${fail} failed (dir: ${DEST_DIR})."
[[ ${fail} -eq 0 ]]
