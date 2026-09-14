#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Composes a ClusterImageCatalog from the one CloudNativePG publishes for the
# upstream extensions, plus the extensions that only exist in this fork.
#
# Upstream refreshes its catalog weekly with digest-pinned references, so this
# fork does not rebuild the extensions it does not own: it consumes them and
# appends its own. See FORK.md.
#
# Usage:
#   hack/compose-extension-catalog.sh <distro> <citus-image-ref> [pg-major]
#
# Environment:
#   CATALOG_OWNER   GitHub owner publishing the result (default maarlab-rethinking)
#
# Example:
#   hack/compose-extension-catalog.sh trixie \
#     ghcr.io/maarlab-rethinking/citus:14.2.0-202608211200-18-trixie@sha256:abc... \
#     > catalog-extensions-trixie.yaml
set -euo pipefail

DISTRO="${1:?usage: $0 <distro> <citus-image-ref> [pg-major]}"
CITUS_IMAGE="${2:?usage: $0 <distro> <citus-image-ref> [pg-major]}"
PG_MAJOR="${3:-18}"
OWNER="${CATALOG_OWNER:-maarlab-rethinking}"

UPSTREAM_CATALOG="https://raw.githubusercontent.com/cloudnative-pg/artifacts/main/image-catalogs-extensions/catalog-minimal-${DISTRO}.yaml"

curl -fsSL "$UPSTREAM_CATALOG" | yq eval "
  (.spec.images[] | select(.major == ${PG_MAJOR}) | .extensions) +=
    [{
      \"name\": \"citus\",
      \"image\": {\"reference\": \"${CITUS_IMAGE}\"},
      \"ld_library_path\": [\"system\"]
    }]
  | (.spec.images[] | select(.major == ${PG_MAJOR}) | .extensions) |= sort_by(.name)
  | .metadata.name = \"postgresql-minimal-${DISTRO}-${OWNER}\"
  | .metadata.labels.\"images.cnpg.io/publisher\" = \"${OWNER}\"
" -
