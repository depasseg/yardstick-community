# Yardstick (https://yardstickhome.com): Yarbo lawn-robot telemetry recorder, map editor and
# scheduler, packaged for containers from the vendor's official .deb, verified against their
# signed release list (https://yardstickhome.com/release/latest.json).
#
# The binary inside is proprietary (Yardstick Technologies LLC; EULA in
# /usr/share/doc/yardstick/EULA.txt). This image is published with their permission.
#
# Build for the host's architecture (amd64 or arm64; the .deb is downloaded during the build):
#   docker build -t yardstick .
# Pin a version (fails if the release list serves another version):
#   docker build --build-arg YARDSTICK_VERSION=1.2.8 -t yardstick:1.2.8 .

# --- fetch and verify the vendor package -------------------------------------------------------
FROM debian:trixie-slim@sha256:f6b08b09a05725f9431502d3b5714f5c4576e82c1a84fa1debe0c24a7e0c3ec4 AS deb
ARG TARGETARCH
# The vendor's release list: version, per-architecture download URL and SHA-256.
ARG RELEASE_URL=https://yardstickhome.com/release/latest.json
# Optional: the exact version this build must produce.
ARG YARDSTICK_VERSION=
RUN set -eux; \
    apt-get update; apt-get install -y --no-install-recommends ca-certificates curl jq; \
    curl -fsSL --retry 3 -o /release.json "${RELEASE_URL}"; \
    version="$(jq -er .version /release.json)"; \
    url="$(jq -er ".linux.${TARGETARCH}.url" /release.json)"; \
    sha256="$(jq -er ".linux.${TARGETARCH}.sha256" /release.json)"; \
    if [ -n "${YARDSTICK_VERSION}" ] && [ "$version" != "${YARDSTICK_VERSION}" ]; then \
      echo "release list serves Yardstick $version, expected ${YARDSTICK_VERSION}" >&2; exit 1; fi; \
    curl -fsSL --retry 3 -o /yardstick.deb "$url"; \
    echo "${sha256}  /yardstick.deb" | sha256sum -c -; \
    [ "$(dpkg-deb -f /yardstick.deb Version)" = "$version" ]; \
    [ "$(dpkg-deb -f /yardstick.deb Architecture)" = "${TARGETARCH}" ]; \
    # Unpack here, not onto the runtime image's /: the package carries a lib/systemd/ directory,
    # and extracting it over Debian's /lib -> usr/lib symlink replaces the symlink with a plain
    # directory (which breaks the dynamic loader on arm64). Only /opt and the docs are copied over.
    dpkg-deb -x /yardstick.deb /pkg; \
    echo "$version" > /pkg/opt/yardstick/VERSION

# --- runtime image -----------------------------------------------------------------------------
FROM debian:trixie-slim@sha256:f6b08b09a05725f9431502d3b5714f5c4576e82c1a84fa1debe0c24a7e0c3ec4
# The package's files, minus its systemd units. The maintainer scripts don't run; the container
# replaces what postinst does (user, data dir, service).
COPY --from=deb /pkg/opt/yardstick /opt/yardstick
COPY --from=deb /pkg/usr/share/doc/yardstick /usr/share/doc/yardstick

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates tzdata curl; \
    rm -rf /var/lib/apt/lists/*; \
    ln -s /opt/yardstick/yardstick /usr/bin/yardstick; \
    useradd --system --uid 1000 --user-group --home-dir /var/lib/yardstick \
            --shell /usr/sbin/nologin --comment "Yardstick recorder" yardstick; \
    mkdir -p /var/lib/yardstick; chown yardstick:yardstick /var/lib/yardstick; \
    /opt/yardstick/yardstick --version

# Same environment as the vendor's systemd unit: data lives in /var/lib/yardstick/yardstick/.
ENV XDG_DATA_HOME=/var/lib/yardstick \
    HOME=/var/lib/yardstick \
    PYTHONUNBUFFERED=1

LABEL org.opencontainers.image.title="Yardstick" \
      org.opencontainers.image.description="Yardstick (yardstickhome.com), the Yarbo recorder, map editor and scheduler, from the vendor .deb" \
      org.opencontainers.image.url="https://yardstickhome.com" \
      org.opencontainers.image.vendor="Yardstick Technologies LLC" \
      org.opencontainers.image.licenses="LicenseRef-Yardstick-EULA"

USER 1000:1000
WORKDIR /var/lib/yardstick
VOLUME /var/lib/yardstick
EXPOSE 8477
# The vendor unit stops it with SIGINT (closes the SQLite WAL cleanly), 30 s grace.
STOPSIGNAL SIGINT
HEALTHCHECK --interval=30s --timeout=5s --start-period=3m --retries=3 \
  CMD curl -fsS -o /dev/null http://127.0.0.1:8477/api/status || exit 1
ENTRYPOINT ["/opt/yardstick/yardstick"]
CMD ["serve", "--port", "8477", "--note", "container"]
