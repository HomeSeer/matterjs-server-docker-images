#!/bin/bash
# Compares the vendored Dockerfile and healthcheck.sh against upstream's copies at a
# given release tag.
#
# The vendored Dockerfile carries exactly one deliberate change: the base image is
# lifted into an overridable ARG so 32-bit ARM can pin an older Node. That change is
# reapplied to upstream's file here, so a clean run means "identical apart from the
# ARG", and any other upstream edit — a new system package, a changed ENTRYPOINT —
# shows up as a real diff.
#
# Usage: scripts/check-upstream-drift.sh 1.4.0
set -uo pipefail

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
    echo "usage: $0 <matter-server version, e.g. 1.4.0>" >&2
    exit 2
fi

UPSTREAM_RAW="https://raw.githubusercontent.com/matter-js/matterjs-server/v${VERSION}/docker/matterjs-server"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fetch() {
    if ! curl -sfL "${UPSTREAM_RAW}/$1" -o "${tmp}/$1"; then
        echo "ERROR: could not fetch $1 from tag v${VERSION} — does that release exist?" >&2
        exit 2
    fi
}

fetch Dockerfile
fetch healthcheck.sh

# Reapply our one deliberate change to upstream's copy before comparing.
sed -E 's|^FROM (node:.*)$|ARG BASE_IMAGE=\1\nFROM ${BASE_IMAGE}|' \
    "${tmp}/Dockerfile" > "${tmp}/Dockerfile.expected"

drift=0
if ! diff -u "${tmp}/Dockerfile.expected" "${here}/Dockerfile" \
    --label "upstream v${VERSION} (ARG patch applied)" --label "vendored"; then
    drift=1
fi
if ! diff -u "${tmp}/healthcheck.sh" "${here}/healthcheck.sh" \
    --label "upstream v${VERSION}" --label "vendored"; then
    drift=1
fi

if [[ "$drift" -eq 0 ]]; then
    echo "No drift: vendored files match upstream v${VERSION}."
else
    echo
    echo "DRIFT DETECTED against upstream v${VERSION}."
    echo "Review the diff above and re-vendor if the change should be carried:"
    echo "  curl -sfL ${UPSTREAM_RAW}/Dockerfile -o Dockerfile"
    echo "  curl -sfL ${UPSTREAM_RAW}/healthcheck.sh -o healthcheck.sh"
    echo "  # then reapply the ARG BASE_IMAGE patch to the FROM line"
fi
exit "$drift"
