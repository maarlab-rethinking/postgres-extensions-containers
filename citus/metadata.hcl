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
        // renovate: registryUrl=https://repos.citusdata.com/community/debian?suite=bookworm&components=main&binaryArch=amd64 depName=postgresql-18-citus-14.2
        package = "14.2.0.citus-1"
        // The SQL version is not derivable from the package version: the
        // `14.2.0.citus-1` package installs SQL scripts numbered `14.2-1`.
        // Renovate cannot maintain this line; bump it by hand alongside
        // `package` above. A stale value fails the E2E tests loudly.
        sql     = "14.2-1"
      }
    }
    trixie = {
      "18" = {
        // renovate: registryUrl=https://repos.citusdata.com/community/debian?suite=trixie&components=main&binaryArch=amd64 depName=postgresql-18-citus-14.2
        package = "14.2.0.citus-1"
        // See the note on the bookworm `sql` attribute above.
        sql     = "14.2-1"
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

  // Citus Data's `arm64` component stops at PostgreSQL 17: as of 2026-10-16 it
  // carries `postgresql-{15,16,17}-citus-13.4` and no `postgresql-18-citus-*`,
  // on either bookworm or trixie. Drop this pin once that package appears —
  // nothing else here is architecture-specific. Replacing the list works
  // because `docker-bake.hcl` comes first in the file chain.
  platforms = [
    "linux/amd64"
  ]

  args = {
    CITUS_MAJOR = "14.2"
  }
}
