# SPDX-FileCopyrightText: Copyright © contributors to CloudNativePG, established as CloudNativePG a Series of LF Projects, LLC.
# SPDX-License-Identifier: Apache-2.0
metadata = {
  name                     = "citus"
  sql_name                 = "citus"
  image_name               = "citus"
  licenses                 = [ "AGPL-3.0-or-later", "PostgreSQL", "curl", "MIT",
                               "BSD-3-Clause", "ISC", "LGPL-2.1-or-later", "X11" ]
  shared_preload_libraries = ["citus"]
  postgresql_parameters    = {}
  extension_control_path   = []
  dynamic_library_path     = []
  ld_library_path          = ["system"]
  bin_path                 = []
  env                      = {}
  auto_update_os_libs      = false
  required_extensions      = []
  create_extension         = true

  versions = {
    bookworm = {
      "18" = {
        // The hint points Renovate at the `arm64` component on purpose. Citus
        // Data publishes fewer builds there than for `amd64`, so a version that
        // exists on `arm64` exists on both, and no bump can leave this
        // multi-architecture build with half a manifest.
        // renovate: registryUrl=https://repos.citusdata.com/community/debian?suite=bookworm&components=main&binaryArch=arm64 depName=postgresql-18-citus-14.3
        package = "14.3.0.citus-1"
        // The SQL version is not derivable from the package version: the
        // `14.3.0.citus-1` package installs SQL scripts numbered `14.3-1`.
        // Renovate cannot maintain this line; bump it by hand alongside
        // `package` above. A stale value fails the E2E tests loudly.
        sql     = "14.3-1"
      }
    }
    trixie = {
      "18" = {
        // See the note on the bookworm `binaryArch` above.
        // renovate: registryUrl=https://repos.citusdata.com/community/debian?suite=trixie&components=main&binaryArch=arm64 depName=postgresql-18-citus-14.3
        package = "14.3.0.citus-1"
        // See the note on the bookworm `sql` attribute above.
        sql     = "14.3-1"
      }
    }
  }
}

// Re-declare name + matrix (matching docker-bake.hcl) so the matrix-expanded
// targets merge by name and pick up the extra CITUS_MAJOR build arg.
target "default" {
  name = getBuildName(metadata.name, build.distro, build.pgVersion)
  matrix = {
    build = getBuildMatrix()
  }

  // No `platforms` override: this image is built for every architecture
  // `docker-bake.hcl` declares. Citus Data's `arm64` component carries
  // `postgresql-18-citus-14.3`, so nothing here is architecture-specific any
  // more. Going back to a series without an `arm64` build for PostgreSQL 18
  // — anything before 14.3 — means restoring `platforms = [ "linux/amd64" ]`
  // here, which replaces the list rather than merging into it because
  // `docker-bake.hcl` comes first in the file chain.
  //
  // `CITUS_MAJOR` is the Debian package's major.minor, which is part of its
  // name (`postgresql-18-citus-14.3`); keep it in step with `package` above.
  args = {
    CITUS_MAJOR = "14.3"
  }
}
