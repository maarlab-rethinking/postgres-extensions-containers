#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Prints the published Citus image for a distribution, pinned by digest:
#
#   ghcr.io/<owner>/citus:<version>-<pg-major>-<distro>@sha256:<digest>
#
# The tag is not assembled here. `docker buildx bake --print` is asked for it,
# so the version always comes from citus/metadata.hcl through the same parsing
# rules the build uses, and there is no second copy to keep in step.
#
# Usage:
#   hack/resolve-citus-image.sh <distro> [pg-major]
#
# Environment:
#   CATALOG_OWNER      GitHub owner publishing the images (default maarlab-rethinking)
#   CITUS_IMAGE_REPO   full repository, overriding CATALOG_OWNER
set -euo pipefail

DISTRO="${1:?usage: $0 <distro> [pg-major]}"
PG_MAJOR="${2:-18}"

OWNER="${CATALOG_OWNER:-maarlab-rethinking}"
IMAGE_REPO="${CITUS_IMAGE_REPO:-ghcr.io/${OWNER}/citus}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Every target carries two tags: a stable one and the same with a build
# timestamp. The stable tag is the one a catalog should name, since the digest
# is what pins the image anyway.
mapfile -t TAGS < <(
  docker buildx bake -f "${ROOT}/docker-bake.hcl" -f "${ROOT}/citus/metadata.hcl" --print 2>/dev/null |
    jq -r --arg suffix "-${PG_MAJOR}-${DISTRO}" '
      [ .target[].tags[]?
        | select(endswith($suffix))
        | select(test("-[0-9]{12}" + $suffix + "$") | not)
        | split(":") | last
      ] | unique | .[]
    '
)

if [ "${#TAGS[@]}" -ne 1 ]; then
  echo "$0: expected exactly one stable tag for ${PG_MAJOR}/${DISTRO}, got ${#TAGS[*]:-none}" >&2
  exit 1
fi

DIGEST="$(docker buildx imagetools inspect "${IMAGE_REPO}:${TAGS[0]}" --format '{{.Manifest.Digest}}')"

printf '%s:%s@%s\n' "${IMAGE_REPO}" "${TAGS[0]}" "${DIGEST}"
