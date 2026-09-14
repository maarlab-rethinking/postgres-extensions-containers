# Citus
<!--
SPDX-FileCopyrightText: Copyright © contributors to CloudNativePG, established as CloudNativePG a Series of LF Projects, LLC.
SPDX-License-Identifier: Apache-2.0
-->

[Citus](https://www.citusdata.com/) turns PostgreSQL into a distributed
database. It transparently shards tables across nodes, parallelises queries,
and adds a columnar table access method (`citus_columnar`). For more
information, see the [official documentation](https://docs.citusdata.com/).

> [!IMPORTANT]
> Citus is licensed under the **AGPL-3.0**, unlike the other extensions in this
> repository. Review the implications for your deployment before using this
> image.

## Prerequisites

Citus differs from the other extensions in this repository in three ways that
affect how you consume the image:

- **`shared_preload_libraries` is mandatory.** Citus refuses to work unless it
  is preloaded; `CREATE EXTENSION citus` fails otherwise.
- **`amd64` only.** Citus Data publishes no `arm64` packages, so this image is
  single-architecture and cannot be used on `arm64` nodes. Third parties do
  build Citus for `arm64` — Pigsty is one — but those packages are outside the
  chain of trust this image relies on: the Citus Data apt repository and the
  key in [`citusdata-community.asc`](citusdata-community.asc).
- **Single-node Citus.** A CloudNativePG `Cluster` is one primary with
  replicas, not a coordinator plus workers. The image gives you
  [Citus on a single node](https://docs.citusdata.com/en/stable/get_started/single_node.html):
  sharding, columnar storage and the full Citus SQL surface, but no horizontal
  scale-out. Building a multi-node cluster means running several
  CloudNativePG `Cluster` resources and registering the workers with
  `citus_add_node()` yourself.

## Usage

The examples below name the image directly, which is the form that keeps
upgrades under your control. If you would rather reference a catalog and let
CloudNativePG resolve the images, [`../catalogs`](../catalogs) publishes one
with this image already in it.

### 1. Add the Citus extension image to your Cluster

Define the `citus` extension under the `postgresql.extensions` section of your
`Cluster` resource, and preload the library:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: cluster-citus
spec:
  imageName: ghcr.io/cloudnative-pg/postgresql:18-minimal-trixie
  instances: 1

  storage:
    size: 1Gi

  postgresql:
    shared_preload_libraries:
    - citus
    extensions:
    - name: citus
      image:
        # renovate: registryUrl=https://repos.citusdata.com/community/debian?suite=trixie&components=main&binaryArch=amd64 depName=postgresql-18-citus-14.2
        reference: ghcr.io/cloudnative-pg/citus:14.2.0-18-trixie
      ld_library_path:
      - system
```

The `ld_library_path` entry is required: `citus.so` links against `libcurl`,
which is not part of the `minimal` base images, so the image ships it under
`/system`.

### 2. Enable the extension in a database

You can install `citus` in a specific database by creating or updating a
`Database` resource. For example, to enable it — together with the columnar
access method — in the `app` database:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Database
metadata:
  name: cluster-citus-app
spec:
  name: app
  owner: app
  cluster:
    name: cluster-citus
  extensions:
  - name: citus
    version: '14.2-1'
  - name: citus_columnar
    version: '14.2-1'
```

> [!NOTE]
> The version to declare here is the **SQL extension version** (`14.2-1`), not
> the upstream release number (`14.2.0`) reported by `citus_version()` and used
> in the image tag. The two never match for Citus: the package
> `14.2.0.citus-1` installs SQL scripts numbered `14.2-1`. The image carries it
> in the `io.cloudnativepg.image.sql.version` label, which is what the
> end-to-end tests read.

### 3. Verify installation

Once the database is ready, connect to it with `psql` and run:

```sql
\dx
```

You should see `citus` and `citus_columnar` listed among the installed
extensions. To check that Citus is actually loaded and functional:

```sql
SELECT citus_version();
CREATE TABLE items (id bigint PRIMARY KEY, payload text);
SELECT create_distributed_table('items', 'id');
```

### 4. Verify OS dependencies are properly satisfied

Citus requires `libcurl` and its transitive dependencies, which are provided
via the `system` directory. CloudNativePG makes them available to PostgreSQL by
adding the directory to `LD_LIBRARY_PATH` for the PostgreSQL process.

To verify that all Citus shared library requirements are being properly
satisfied, connect to the container and run:

```bash
cd /extensions/citus/lib
LD_LIBRARY_PATH=/extensions/citus/system ldd citus*.so
```

Make sure there are no missing shared libraries.

## Maintenance notes

Two things do not work the way they do for the PGDG-based extensions in this
repository, and need attention when bumping versions:

- **The package does not come from PGDG.** Citus is not part of the PostgreSQL
  Global Development Group apt repository; it is published by Citus Data at
  `repos.citusdata.com`. The repository signing key is vendored in this folder
  as `citusdata-community.asc` (fingerprint
  `E6FF C1A8 E256 1FC0 04D1 847F 56F4 FA44 1530 DF18`) so that the trust root
  is pinned and auditable rather than fetched during the build. Renovate reads
  the `registryUrl=` hint in `metadata.hcl` to look versions up there.
- **The Debian package name carries the Citus `major.minor`**
  (`postgresql-18-citus-14.2`). Renovate can therefore only track patch
  releases within a series. Moving to a new series is a manual change to the
  `CITUS_MAJOR` build argument and the `depName=` hints in `metadata.hcl`.
- **The `sql` attribute cannot be automated.** For every other extension in
  this repository Renovate derives it from the package version with an
  `extractVersion` regex. No regex turns `14.2.0.citus-1` into `14.2-1`, so
  both the `sql` attributes in `metadata.hcl` and the `version` fields of the
  `Database` example above are maintained by hand and carry no `# renovate:`
  hint. A stale value fails the end-to-end tests loudly rather than silently.

## Contributors

This extension is maintained by:

- Maarlab Rethinking (@maarlab-rethinking)

The maintainers are responsible for:

- Monitoring upstream releases and security vulnerabilities.
- Ensuring compatibility with supported PostgreSQL versions.
- Reviewing and merging contributions specific to this extension's container
  image and lifecycle.

---

## Licenses and Copyright

This container image contains software that may be licensed under various
open-source licenses.

All relevant license and copyright information for the `citus` extension
and its dependencies are bundled within the image at:

```text
/licenses/
```

By using this image, you agree to comply with the terms of the licenses
contained therein.
