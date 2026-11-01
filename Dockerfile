# Yardstick (https://yardstickhome.com): Yarbo lawn-robot telemetry recorder, map editor and
# scheduler, packaged for containers from the vendor's official yardstick_amd64.deb.
#
# The binary inside is proprietary (Yardstick Technologies LLC; EULA in
# /usr/share/doc/yardstick/EULA.txt). This image is published with their permission.
#
# Build (the .deb is downloaded during the build):
#   docker build -t yardstick .
# Pin a version (fails if the download isn't that version):
#   docker build --build-arg YARDSTICK_VERSION=1.2.7 -t yardstick:1.2.7 .

# renovate: datasource=docker depName=debian
ARG BASE=debian:trixie-slim

# --- fetch the vendor package ------------------------------------------------------------------
FROM ${BASE} AS deb
ARG DEB_URL=https://yardstickhome.com/download/yardstick_amd64.deb
# Optional: the exact version this build must produce (as in the package's control file).
ARG YARDSTICK_VERSION=
RUN set -eux; \
    apt-get update; apt-get install -y --no-install-recommends ca-certificates curl; \
    curl -fsSL --retry 3 -o /yardstick_amd64.deb "${DEB_URL}"; \
    v="$(dpkg-deb -f /yardstick_amd64.deb Version)"; \
    [ "$(dpkg-deb -f /yardstick_amd64.deb Architecture)" = amd64 ]; \
    if [ -n "${YARDSTICK_VERSION}" ] && [ "$v" != "${YARDSTICK_VERSION}" ]; then \
      echo "downloaded Yardstick $v, expected ${YARDSTICK_VERSION}" >&2; exit 1; fi; \
    echo "$v" > /yardstick.version

# --- runtime image -----------------------------------------------------------------------------
FROM ${BASE}
COPY --from=deb /yardstick_amd64.deb /yardstick.version /tmp/

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates tzdata curl; \
    rm -rf /var/lib/apt/lists/*; \
    # Unpack without running the maintainer scripts; the container replaces what postinst does
    # (user, data dir, systemd units).
    dpkg-deb -x /tmp/yardstick_amd64.deb /; \
    rm -f /tmp/yardstick_amd64.deb; \
    rm -rf /lib/systemd/system/yardstick*; \
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
