#!/bin/bash
# Compares the vendored Dockerfile and healthcheck.sh against upstream's copies at a
# given release tag.
#
# The vendored Dockerfile carries exactly one deliberate change: the base image is
# lifted into an overridable ARG so 32-bit ARM can pin an older Node. The ARG is
# declared at the top of the file, ahead of upstream's `FROM scratch AS npm-packages`
# stage — an ARG declared inside a stage is invisible to a later FROM. That change is
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

drift=0

# Reapply our one deliberate change to upstream's copy before comparing: a global
# ARG BASE_IMAGE at the top of the file, and upstream's node FROM line pointing at it.
mapfile -t bases < <(sed -nE 's|^FROM (node:[^[:space:]]+)$|\1|p' "${tmp}/Dockerfile")
if [[ "${#bases[@]}" -ne 1 ]]; then
    echo "Upstream v${VERSION} Dockerfile has ${#bases[@]} 'FROM node:...' lines, expected 1;" \
        "the ARG BASE_IMAGE patch needs revisiting." >&2
    drift=1
fi
{
    echo "# Local patch: base image as a global ARG (before the first FROM) so armv7 can pin Node 22."
    echo "ARG BASE_IMAGE=${bases[0]:-}"
    echo
    sed -E 's|^FROM node:[^[:space:]]+$|FROM ${BASE_IMAGE}|' "${tmp}/Dockerfile"
} > "${tmp}/Dockerfile.expected"

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
    echo "  # then reapply the ARG BASE_IMAGE patch (README.md, \"Vendored files\")"
fi
exit "$drift"
