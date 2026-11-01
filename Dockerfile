# Yardstick (https://yardstickhome.com): Yarbo lawn-robot telemetry recorder, map editor and
# scheduler, packaged for containers from the vendor's official .deb. The package's SHA-256 and
# Ed25519 signature are checked against the vendor's release list
# (https://yardstickhome.com/release/latest.json) before anything is unpacked.
#
# The binary inside is proprietary (Yardstick Technologies LLC; EULA in
# /usr/share/doc/yardstick/EULA.txt). This image is published with their permission.
#
# Build for the host's architecture (amd64 or arm64; the .deb is downloaded during the build):
#   docker build -t yardstick .
# Pin a version (fails if the release list serves another version):
#   docker build --build-arg YARDSTICK_VERSION=1.2.8 -t yardstick:1.2.8 .
# Test-channel builds (testers only; the downloads need your licence key):
#   docker build --build-arg RELEASE_URL=https://yardstickhome.com/release/testing.json \
#     --secret id=yardstick_license,env=YARDSTICK_LICENSE -t yardstick:test .

# --- fetch and verify the vendor package -------------------------------------------------------
FROM debian:trixie-slim@sha256:f6b08b09a05725f9431502d3b5714f5c4576e82c1a84fa1debe0c24a7e0c3ec4 AS deb
ARG TARGETARCH
# The vendor's release list: version, per-architecture download URL, SHA-256 and signature.
# latest.json = stable; testing.json = the test channel (needs the licence key, see above).
ARG RELEASE_URL=https://yardstickhome.com/release/latest.json
# Optional: the exact version this build must produce.
ARG YARDSTICK_VERSION=
# Yardstick Technologies' Ed25519 release-signing key (raw public key, hex), from Mike Gustin,
# 2026-11-01. Yardstick itself checks Linux updates against the same key.
ARG SIGNING_KEY=912aee1dfecfba51562d30b98b433ba89c95b4612d6b60fc92eec7536b5a1323
RUN --mount=type=secret,id=yardstick_license,required=false \
    set -eux; \
    apt-get update; apt-get install -y --no-install-recommends ca-certificates curl jq openssl; \
    # Test-channel downloads answer only to Yardstick-like clients with a licence key.
    hdr=""; if [ -s /run/secrets/yardstick_license ]; then \
      hdr="X-Yardstick-License: $(cat /run/secrets/yardstick_license)"; fi; \
    fetch() { curl -fsSL --retry 3 -A "yardstick-community-build" ${hdr:+-H "$hdr"} -o "$1" "$2"; }; \
    fetch /release.json "${RELEASE_URL}"; \
    version="$(jq -er .version /release.json)"; \
    url="$(jq -er ".linux.${TARGETARCH}.url" /release.json)"; \
    sha256="$(jq -er ".linux.${TARGETARCH}.sha256" /release.json)"; \
    signature="$(jq -er ".linux.${TARGETARCH}.signature" /release.json)"; \
    if [ -n "${YARDSTICK_VERSION}" ] && [ "$version" != "${YARDSTICK_VERSION}" ]; then \
      echo "release list serves Yardstick $version, expected ${YARDSTICK_VERSION}" >&2; exit 1; fi; \
    fetch /yardstick.deb "$url"; \
    echo "${sha256}  /yardstick.deb" | sha256sum -c -; \
    # Ed25519 over the exact bytes of the .deb. Raw key -> DER SubjectPublicKeyInfo -> PEM.
    # (basenc --base16 wants uppercase hex.)
    hex2bin() { tr a-f A-F | basenc -d --base16; }; \
    { printf '302a300506032b6570032100%s' "${SIGNING_KEY}" | hex2bin | base64 -w0; } > /key.b64; \
    { echo '-----BEGIN PUBLIC KEY-----'; cat /key.b64; echo; echo '-----END PUBLIC KEY-----'; } > /key.pem; \
    printf '%s' "$signature" | hex2bin > /yardstick.sig; \
    openssl pkeyutl -verify -pubin -inkey /key.pem -rawin -in /yardstick.deb -sigfile /yardstick.sig; \
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
# YARDSTICK_CONTAINER: Yardstick reads it to show "pull the newer image" instead of its own
# Update button, which can't work here (agreed with the vendor, 2026-11-01).
ENV XDG_DATA_HOME=/var/lib/yardstick \
    HOME=/var/lib/yardstick \
    PYTHONUNBUFFERED=1 \
    YARDSTICK_CONTAINER=1

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
