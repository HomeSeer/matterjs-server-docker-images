# matterjs-server-docker-images

Packaging repo that republishes [matter-js/matterjs-server](https://github.com/matter-js/matterjs-server)
container images with **linux/arm/v7** support added.

Upstream publishes `linux/amd64` and `linux/arm64` only. The HomeSeer Matter Controller
plugin needs to run on 32-bit ARM devices as well, so this repo builds that one missing
architecture and republishes all three under a single tag.

## What the published image contains

| Platform | Origin | Node |
|---|---|---|
| `linux/amd64` | upstream's release image, referenced by digest | 24 |
| `linux/arm64` | upstream's release image, referenced by digest | 24 |
| `linux/arm/v7` | built here from the vendored `Dockerfile` | 22 |

amd64 and arm64 are **not** rebuilt. The workflow references upstream's published digests,
so those two architectures are bit-identical to what upstream ships — this is a mirror for
them, not a re-derivation.

### Why armv7 is on Node 22

Node 24 ships no 32-bit ARM build, and neither does any Debian trixie Node image. Node 22
bookworm is the newest base offering `linux/arm/v7`, and it still satisfies upstream's
`engines: >=22.13.0`. The vendored `Dockerfile` lifts the base image into an overridable
`ARG BASE_IMAGE` for exactly this reason; nothing else about it is changed.

This means one tag carries two different Node majors. That is deliberate and is the
standard way to keep a dropped architecture alive, but it is worth knowing: if a bug
appears on armv7 and nowhere else, the Node version difference is the first thing to
suspect.

### Known armv7 constraints

- **Heap ceiling.** 32-bit V8 caps old-space near 1 GB regardless of
  `--max-old-space-size`. Large Matter networks may not fit.
- **Node 22 is terminal.** Node 24 dropped 32-bit ARM, so there is no upgrade path.
  Node 22 reaches end-of-life in April 2027.
- **BLE may be absent.** `@matter/nodejs-ble` is an optional dependency; if it fails to
  compile on armhf the image still builds, silently without BLE. Check the build log if
  BLE commissioning is needed.

## Publishing a version

Actions → **Build and publish** → Run workflow.

| Input | Meaning |
|---|---|
| `version` | Upstream matter-server version to package, e.g. `1.4.0`. Also the primary tag. |
| `extra_tags` | Optional, comma-separated, e.g. `latest,stable`. |
| `ignore_drift` | Publish even if the vendored files no longer match upstream. |

The workflow runs three jobs: a drift check against upstream, the armv7 build, then the
merge. The merge job fails rather than publishing if the resulting manifest does not
cover all three platforms — a partially-merged tag would silently omit somebody's
architecture, which is worse than a failed run.

The registry owner is derived from `github.repository_owner`, so this repo can be
transferred to another organization and it will publish to the new owner's namespace with
no edit to the workflow.

## Vendored files

`Dockerfile` and `healthcheck.sh` are copied from upstream's `docker/matterjs-server/`.
The only local modification is the `ARG BASE_IMAGE` line.

Check them against any upstream release:

```bash
scripts/check-upstream-drift.sh 1.4.0
```

It reapplies the `ARG BASE_IMAGE` patch to upstream's copy before diffing, so a clean run
means "identical apart from our one deliberate change". CI runs this before every publish
and refuses to build on drift unless `ignore_drift` is set.

When upstream does change these files, re-vendor:

```bash
V=1.4.0
BASE=https://raw.githubusercontent.com/matter-js/matterjs-server/v$V/docker/matterjs-server
curl -sfL $BASE/Dockerfile -o Dockerfile
curl -sfL $BASE/healthcheck.sh -o healthcheck.sh
```

then reapply the patch — replace the `FROM node:...` line with:

```dockerfile
ARG BASE_IMAGE=node:24-trixie-slim
FROM ${BASE_IMAGE}
```

and re-run the drift check to confirm it comes back clean.

## Consuming from the plugin

The HomeSeer Matter Controller plugin pulls this image by tag and lets Docker resolve the
architecture. It needs no architecture detection of its own — that is the entire point of
publishing one merged manifest rather than per-architecture tags.

```bash
docker pull ghcr.io/<owner>/matterjs-server:1.4.0
```

## Release checklist

Because the plugin pins a version, the mirror and the pin must move together:

1. Run **Build and publish** for the new upstream version.
2. Confirm the run summary lists all three platforms.
3. Verify the package is **public** — new GHCR packages default to private, and a private
   package presents on a user's device as an auth failure, not an obvious misconfiguration.
4. Bump `MATTER_JS_SERVER_VERSION` in the plugin and ship.

Skipping step 1 means the plugin cannot upgrade; skipping step 3 means it cannot pull at
all.
