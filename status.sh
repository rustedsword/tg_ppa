#!/usr/bin/env bash
# One-glance state of ppa:lightofmysoul/tg.
#
# Shows what each of our branches is packaging against the commit Telegram
# Desktop actually pins, so pin drift after an upstream bump is obvious, and
# what the PPA currently holds.
set -euo pipefail

PPA_OWNER="${PPA_OWNER:-lightofmysoul}"
PPA_NAME="${PPA_NAME:-tg}"
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
LP="https://api.launchpad.net/devel"

command -v curl >/dev/null || { echo "need curl" >&2; exit 1; }
command -v jq   >/dev/null || { echo "need jq"   >&2; exit 1; }

PREPARE="${ROOT}/tdesktop/Telegram/build/prepare/prepare.py"

# The commit each stage('<name>', ...) block checks out in prepare.py, either
# literally or through a Python variable such as tlottieRevision.
pinned_commit() {
    [ -f "${PREPARE}" ] || { echo "?"; return; }
    local pin
    pin="$(awk -v stage="stage('$1'" '
        index($0, stage) == 1 { inside = 1; next }
        inside && /git checkout/ { print ($3 == "\"\"\"" ? $5 : $3); exit }
        inside && /^stage\(/ { exit }
    ' "${PREPARE}")"
    if [[ "${pin}" =~ ^[0-9a-f]+$ ]] || [ -z "${pin}" ]; then
        echo "${pin}"
    else
        sed -n "s/^${pin} = '\([0-9a-f]*\)'$/\1/p" "${PREPARE}"
    fi
}

# What our branch is built from, per debian/changelog.
packaged_version() {
    local dir="${ROOT}/$1"
    [ -f "${dir}/debian/changelog" ] || { echo "—"; return; }
    sed -n '1s/.*(\([^)]*\)).*/\1/p' "${dir}/debian/changelog"
}

# Our branches carry packaging commits on top of the upstream commit they were
# cut from, so the pin must be an *ancestor* of HEAD — comparing it to HEAD
# directly would flag every branch as drifted.
contains_pin() {
    local dir="${ROOT}/$1" pin="$2"
    git -C "${dir}" merge-base --is-ancestor "${pin}" HEAD 2>/dev/null
}

echo "== pinned by tdesktop vs packaged =="
printf '  %-14s %-10s %-8s %s\n' component pinned state version
# stage, checkout holding the pin, package
for triple in "tg_owt tg_owt tg_owt" "tde2e tde2e tde2e" "rnnoise rnnoise rnnoise" \
        "tlottie tdesktop_rust/tlottie tdesktop_rust" \
        "wallet-engine tdesktop_rust/wallet-engine tdesktop_rust"; do
    set -- $triple
    pin="$(pinned_commit "$1")"
    ver="$(packaged_version "$3")"
    if [ -z "${pin}" ] || [ "${pin}" = "?" ]; then
        state="no-pin"
    elif contains_pin "$2" "${pin}"; then
        state="ok"
    else
        state="DRIFT"
    fi
    printf '  %-14s %-10s %-8s %s\n' "$1" "${pin:0:9}" "${state}" "${ver}"
done

echo "== ppa:${PPA_OWNER}/${PPA_NAME} =="
curl -fsSG "${LP}/~${PPA_OWNER}/+archive/ubuntu/${PPA_NAME}" \
    --data-urlencode "ws.op=getPublishedSources" \
| jq -r '.entries[] | [.source_package_name, .source_package_version, .status] | @tsv' \
| column -t -s "$(printf '\t')" | sed 's/^/  /'

echo "== builds =="
curl -fsSG "${LP}/~${PPA_OWNER}/+archive/ubuntu/${PPA_NAME}" \
    --data-urlencode "ws.op=getBuildRecords" \
| jq -r '.entries[] | [.arch_tag, .buildstate, (.title | sub(" build of ";" "))] | @tsv' \
| head -12 | column -t -s "$(printf '\t')" | sed 's/^/  /'
