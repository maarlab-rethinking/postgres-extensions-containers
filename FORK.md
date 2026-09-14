# Fork operating model

This is a fork of
[cloudnative-pg/postgres-extensions-containers](https://github.com/cloudnative-pg/postgres-extensions-containers)
maintained by [@maarlab-rethinking](https://github.com/maarlab-rethinking).

It exists for **one reason**: to build the [`citus`](citus) extension image,
which cannot be contributed upstream. Citus is licensed under the AGPL-3.0,
and the upstream README is explicit that licences outside the
[CNCF Allowlist](https://github.com/cncf/foundation/blob/main/policies-guidance/allowed-third-party-license-policy.md)
are not a precedent for new extensions.

Everything else in this repository is upstream's work, consumed as-is.

## Design rule: never modify a shared file

Most upstream commits touch the shared surface — `Taskfile.yml`,
`.github/workflows/` and `dagger/maintenance/` above all. Every shared file this
fork edits turns into a recurring merge conflict, so the rule is:

> Changes live in `citus/`, plus files upstream does not have (`FORK.md`,
> `hack/`, `catalogs/`, `.github/workflows/citus.yml`,
> `.github/workflows/publish-catalogs.yml`).

Beyond those, the fork only adds: a row and a note in `README.md`, a `CODEOWNERS`
entry, and the Renovate managers for apt repositories outside PGDG.
`docker-bake.hcl`, the `Taskfile`, the shared workflows, the `test/` suite and
the Dagger module stay untouched. Before adding anything, check where the fork
already diverges with `git diff --stat upstream/main..main`.

Two upstream mechanisms make that possible, and are worth remembering before
reaching for a shared file:

- **Per-extension build overrides.** `docker-bake.hcl` comes first in the bake
  file chain, so an extension's own `target "default"` block can *replace* any
  attribute, not just merge into maps. `citus/metadata.hcl` uses this to pin
  `platforms` to `linux/amd64`, since Citus Data publishes no `arm64` packages.
- **Dynamic target discovery.** `.github/workflows/bake.yml` derives the build
  matrix from `dagger call get-targets`, so a new extension directory needs no
  workflow registration.

## What this fork builds

Only `citus`. The other eight extensions are pulled from upstream's public
registry — they are anonymously pullable, digest-pinned and signed, so
rebuilding them here would publish byte-equivalent duplicates.

That matters for CI cost. The `_shared` filter in `bake.yml` is included in
*every* extension's path filter, so any change under `docker-bake.hcl`,
`Taskfile.yml`, `test/` or `dagger/` marks all extensions as changed. Since
most upstream commits touch one of those, pushing a sync would rebuild nine
extensions across two distributions, plus security scans and smoke tests
against three CloudNativePG releases — roughly seventy jobs, to republish
images that already exist upstream.

The fork therefore keeps upstream's workflows on disk untouched but
**disabled**, and drives Citus from its own caller workflow,
[`.github/workflows/citus.yml`](.github/workflows/citus.yml), which reuses
upstream's `bake_targets.yml` with `extension_name: citus`.

A dedicated caller is needed rather than dispatching `bake.yml` by hand: a
disabled workflow cannot be dispatched either, so `bake.yml` has to stay off
permanently.

It builds on `pull_request`, not on every branch push, so a `-testing` tag is
only produced for something under review — and it builds `refs/pull/N/merge`,
which is the merge result rather than the branch alone. Its other trigger is a
push to `main`, which is what `copytoproduction` gates on: production tags
follow a merge, never a review.

### Bringing up the fork, in order

GitHub does not register workflows in a fork until Actions is enabled there, and
`gh workflow disable` needs them registered. Enabling Actions does not replay
past pushes, so the safe sequence is to land the code while nothing can run:

```sh
REPO=maarlab-rethinking/postgres-extensions-containers

# 1. Push with Actions still disabled: no workflow can trigger.
git push origin main

# 2. Enable Actions in the repository's Actions tab ("I understand my
#    workflows, go ahead and enable them"). Nothing runs retroactively.

# 3. Disable upstream's entry points, now that they are registered.
#    bake.yml rebuilds every extension on any shared-file change, and chains a
#    repository_dispatch into update-catalogs.
gh workflow disable -R "$REPO" bake.yml
#    update-catalogs.yml checks out and commits to cloudnative-pg/artifacts,
#    which this fork cannot and must not write to.
gh workflow disable -R "$REPO" update-catalogs.yml
#    update_os_libraries.yml opens a daily PR for extensions with
#    auto_update_os_libs = true. Citus is not one of them: its package name
#    carries the Citus major.minor (postgresql-18-citus-14.2) and lives outside
#    PGDG, which the maintenance tooling cannot express.
gh workflow disable -R "$REPO" update_os_libraries.yml

# 4. Only now push the Citus work. citus.yml builds it for a pull request
#    touching citus/, for a merge to main, or on demand:
gh workflow run citus.yml -R "$REPO"
```

Doing it in the other order — enabling Actions before pushing — is what to
avoid. A sync moves `main` by every upstream commit at once, and those touch
shared files, so `bake.yml` would flag all nine extensions, build them
multi-arch, push them to `ghcr.io/<owner>/<ext>-testing`, sign them, scan them,
smoke-test each against three CloudNativePG releases, and then
`copytoproduction` would promote all of them, because the ref is `main`.

Step 3 is not optional for the two cron-triggered workflows. A fork starts with
its schedules dormant, but that is a consequence of Actions being off, not a
standing exemption: once Actions is enabled the crons resume, and
`update-catalogs.yml` then runs every Monday and fails at the
`cloudnative-pg/artifacts` checkout. `gh workflow list` reporting
`disabled_fork` describes the moment, not a setting — only `disabled_manually`
survives. Disabling `update-catalogs.yml` also blocks the `repository_dispatch`
path that `bake.yml` uses to reach it after a build on `main`.

A workflow already sitting in `disabled_fork` rejects the disable outright —
`HTTP 403: Unable to disable a workflow that is not active` — so reaching the
durable state means arming it for a moment first:

```sh
gh workflow enable  -R "$REPO" update_os_libraries.yml
gh workflow disable -R "$REPO" update_os_libraries.yml
```

Do it away from the workflow's cron (`0 3 * * *` for this one) and the window
costs nothing.

> [!NOTE]
> Neither can write to upstream today, because the fork has no `REPO_GHA_PAT`
> secret and the checkout simply fails. Do not add that secret with write
> access to `cloudnative-pg/artifacts`.

`test.yml` (Dagger module unit tests) is scoped to `dagger/maintenance/**`,
which this fork never modifies, so it can be left enabled.

### Building Citus locally

The upstream tasks work unchanged:

```sh
task bake TARGET=citus
task e2e:test:full TARGET=citus
```

## Image catalogs

A `ClusterImageCatalog` maps a PostgreSQL major to an image and, since
CloudNativePG 1.29, to the extension images that go with it. Upstream publishes
one per distribution in
[`cloudnative-pg/artifacts/image-catalogs-extensions`](https://github.com/cloudnative-pg/artifacts/tree/main/image-catalogs-extensions),
refreshed weekly by its `update-catalogs.yml`.

That catalog lists the nine extensions upstream builds, and cannot list Citus.
Anyone who reaches for a catalog — the way CloudNativePG documents — therefore
cannot consume this fork at all without abandoning catalogs entirely. Closing
that gap is what [`catalogs/`](catalogs) is for: upstream's catalog with the
Citus entry appended, published here.

The relationship with `cloudnative-pg/artifacts` stays **read-only**. Its
catalogs are fetched over HTTPS and never written to, which is why
`update-catalogs.yml` is disabled here rather than adapted: it checks out that
repository with a write token. Forking it would buy nothing — the artifact
needs a stable URL, and this repository already is one.

Two fork-owned scripts do the work, and both are usable by hand:

```sh
# Resolve the published image for a distribution, pinned by digest.
hack/resolve-citus-image.sh trixie
# ghcr.io/maarlab-rethinking/citus:14.2.0-18-trixie@sha256:7de5b522...

# Append it to upstream's catalog.
hack/compose-extension-catalog.sh trixie "$(hack/resolve-citus-image.sh trixie)"
```

`compose-extension-catalog.sh` matches on `major` rather than on a list index,
so it survives upstream adding or retiring a PostgreSQL major, and it renames
the catalog and relabels the publisher so both can coexist in a cluster.
`resolve-citus-image.sh` reads the tag from `docker buildx bake --print`
instead of assembling it, so the version comes from `citus/metadata.hcl`
through the same parsing the build uses — there is no second copy of the rules
to keep in step when Citus is bumped.

`.github/workflows/publish-catalogs.yml` runs the pair weekly, and again after
a Citus image lands on `main`. It signs each catalog with a keyless Sigstore
bundle, as upstream does, and **opens a pull request** instead of committing:
`main` requires one, and these are digest bumps of images built elsewhere.
Signing bundles are regenerated on every run even when the catalog is
byte-identical, so the decision to publish looks at the YAML alone — plus the
case of a bundle that does not exist yet.

## Syncing with upstream

```sh
git remote add upstream https://github.com/cloudnative-pg/postgres-extensions-containers.git
git fetch upstream
git checkout main && git merge upstream/main
```

`main` carries this fork's own commits on top of upstream's, so the sync is an
ordinary merge. Those merge commits are the only merges in `main`: pull requests
are restricted to squash and rebase.

The fork's own diff, at any point:

```sh
git log --oneline upstream/main..main
```

## Known upstream friction

Two hardcoded upstream references would bite if this fork ever published the
full set of images or generated its own catalogs. They are why the model above
avoids both:

- `dagger/maintenance/image.go` builds image references from a hardcoded
  `ghcr.io/cloudnative-pg/<image_name>`, while `docker-bake.hcl` takes a
  `registry` variable. Catalog generation would look for
  `ghcr.io/cloudnative-pg/citus`, which does not exist, and fail the whole run.
- `.github/workflows/update-catalogs.yml` hardcodes the
  `cloudnative-pg/artifacts` repository.

Making the first configurable is a reasonable upstream contribution rather than
a fork patch; see the notes in the pull request tracking it.
