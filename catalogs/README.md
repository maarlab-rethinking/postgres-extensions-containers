# Image catalogs

A `ClusterImageCatalog` maps a PostgreSQL major to a digest-pinned image and,
since CloudNativePG 1.29, to the extension images that go with it. Referencing
one lets a `Cluster` name a major instead of an image.

The catalogs here are [upstream's][upstream] with this fork's Citus image
appended to the PostgreSQL 18 entry. Everything else in them — PostgreSQL 13
through 18 and the nine extensions CloudNativePG builds — is upstream's own
content, passed through unchanged.

> [!IMPORTANT]
> These are **not** the official CloudNativePG catalogs. They carry
> `images.cnpg.io/publisher: maarlab-rethinking` and a `-maarlab-rethinking`
> name suffix so the two can coexist in a cluster. If you do not need Citus,
> use [upstream's][upstream] instead.

## Usage

```sh
kubectl apply -f https://raw.githubusercontent.com/maarlab-rethinking/postgres-extensions-containers/main/catalogs/catalog-minimal-trixie.yaml
```

Or both distributions at once:

```sh
kubectl apply -k https://github.com/maarlab-rethinking/postgres-extensions-containers/catalogs?ref=main
```

A cluster then refers to the catalog rather than to an image, and Citus arrives
with it:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
spec:
  imageCatalogRef:
    apiGroup: postgresql.cnpg.io
    kind: ClusterImageCatalog
    name: postgresql-minimal-trixie-maarlab-rethinking
    major: 18
  postgresql:
    shared_preload_libraries:
      - citus
```

`shared_preload_libraries` stays your responsibility: a catalog supplies images,
not PostgreSQL configuration, and Citus refuses to load without it.

## Before you adopt one

**Applying a catalog delegates upgrades.** Every refresh moves the images its
clusters resolve, and CloudNativePG rolls the cluster to adopt them. That is the
feature, but it means a commit in this repository — or upstream's — schedules a
restart in yours. Pinning `imageName` and the extension images by digest in your
own manifests is the alternative, and it turns the same upgrade into a pull
request you merge when it suits you.

**Citus is `amd64` only.** Citus Data publishes no `arm64` packages, so this
image is single-architecture while the PostgreSQL and upstream extension images
beside it are not. On an `arm64` node the cluster starts and the extension image
fails to pull. Unofficial `arm64` builds exist — Pigsty publishes some — but
they are not what this image is built from. See [`../citus/README.md`](../citus/README.md).

**Citus is AGPL-3.0.** That is why it is not proposed upstream, and it is worth
knowing before it reaches your cluster.

## Verifying

Each catalog is signed with a keyless Sigstore bundle, as upstream does:

```sh
cosign verify-blob catalog-minimal-trixie.yaml \
  --bundle catalog-minimal-trixie.yaml.sigstore.json \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-identity-regexp '^https://github\.com/maarlab-rethinking/postgres-extensions-containers/\.github/workflows/publish-catalogs\.yml@refs/heads/main$'
```

## How they are refreshed

`.github/workflows/publish-catalogs.yml` recomposes and re-signs them weekly,
and again whenever a new Citus image lands on `main`. It opens a pull request
rather than committing: the digests belong to images built elsewhere, so the
change deserves to be looked at.

[upstream]: https://github.com/cloudnative-pg/artifacts/tree/main/image-catalogs-extensions
