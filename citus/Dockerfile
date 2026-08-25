# SPDX-FileCopyrightText: Copyright © contributors to CloudNativePG, established as CloudNativePG a Series of LF Projects, LLC.
# SPDX-License-Identifier: Apache-2.0

ARG BASE=ghcr.io/cloudnative-pg/postgresql:18-minimal-trixie
FROM $BASE AS builder

ARG PG_MAJOR
ARG EXT_VERSION
ARG CITUS_MAJOR

USER 0

# Citus is not part of PGDG: it is published by Citus Data in their own apt
# repository. The signing key is vendored in this folder so that the trust root
# is auditable and pinned, instead of being fetched at build time.
# Key fingerprint: E6FF C1A8 E256 1FC0 04D1 847F 56F4 FA44 1530 DF18
COPY citusdata-community.asc /etc/apt/keyrings/citusdata-community.asc

RUN set -eux && \
	# Initial system libraries
	ldconfig -p | awk '{print $NF}' | grep '^/' | sort | uniq > /tmp/base-image-libs.out && \
	# Install Citus
	echo "deb [signed-by=/etc/apt/keyrings/citusdata-community.asc] https://repos.citusdata.com/community/debian/ $(. /etc/os-release && echo "$VERSION_CODENAME") main" \
		> /etc/apt/sources.list.d/citusdata-community.list && \
	apt-get update && \
	apt-get install -y --no-install-recommends \
		"postgresql-${PG_MAJOR}-citus-${CITUS_MAJOR}=${EXT_VERSION}"

# Gather Citus system libraries and their licenses
RUN mkdir -p /system /licenses && \
	# Get libraries
	ldd /usr/lib/postgresql/${PG_MAJOR}/lib/citus*.so \
		/usr/lib/postgresql/${PG_MAJOR}/lib/citus_decoders/*.so \
		| awk '{print $3}' | grep '^/' | sort | uniq > /tmp/all-deps.out && \
	# Extract all the libs that aren't already part of the base image
	comm -13 /tmp/base-image-libs.out /tmp/all-deps.out > /tmp/libraries.out && \
	while read -r lib; do \
		resolved=$(readlink -f "$lib"); \
		dir=$(dirname "$lib"); \
		base=$(basename "$lib"); \
		# Copy the real file
		cp -a "$resolved" /system/; \
		# Reconstruct all its symlinks
		for file in "$dir"/"${base%.so*}.so"*; do \
			[ -e "$file" ] || continue; \
			# If it's a symlink and it resolves to the same real file, we reconstruct it
			if [ -L "$file" ] && [ "$(readlink -f "$file")" = "$resolved" ]; then \
				ln -sf "$(basename "$resolved")" "/system/$(basename "$file")"; \
			fi; \
		done; \
	done < /tmp/libraries.out && \
	# Get licenses
	for lib in $(find /system -maxdepth 1 -type f -name '*.so*'); do \
		# Get the name of the pkg that installed the library
		pkg=$(dpkg -S "$(basename "$lib")" | grep -v "diversion by" | awk -F: '/:/{print $1; exit}'); \
		[ -z "$pkg" ] && continue; \
		mkdir -p "/licenses/$pkg" && cp -a "/usr/share/doc/$pkg/copyright" "/licenses/$pkg/copyright"; \
	done


FROM scratch
ARG PG_MAJOR
ARG CITUS_MAJOR

# Licenses
COPY --from=builder /licenses /licenses/
COPY --from=builder /usr/share/doc/postgresql-${PG_MAJOR}-citus-${CITUS_MAJOR}/copyright /licenses/postgresql-${PG_MAJOR}-citus-${CITUS_MAJOR}/

# Libraries
COPY --from=builder /usr/lib/postgresql/${PG_MAJOR}/lib/citus*.so /lib/
COPY --from=builder /usr/lib/postgresql/${PG_MAJOR}/lib/citus_decoders/ /lib/citus_decoders/
COPY --from=builder /usr/lib/postgresql/${PG_MAJOR}/lib/bitcode/ /lib/bitcode/

# Share
COPY --from=builder \
	/usr/share/postgresql/${PG_MAJOR}/extension/citus* \
	/usr/share/postgresql/${PG_MAJOR}/extension/columnar* \
	/share/extension/

# System libs
COPY --from=builder /system /system/

USER 65532:65532
