# Yardstick community container image

[Yardstick](https://yardstickhome.com) records your Yarbo lawn robot's telemetry, draws the
yard map, lets you edit it and schedules work, all on your own network. It ships as a `.deb`
for Linux PCs. This repository packages that official `.deb`, unchanged, into a container image
for people who run their home services on Docker, Unraid, Synology, Proxmox or Kubernetes.
Built for **amd64 and arm64** (Raspberry Pi 4/5, ARM NAS boxes); `docker pull` picks the right one.

```
ghcr.io/depasseg/yardstick-community:<version>   # e.g. 1.2.7
ghcr.io/depasseg/yardstick-community:latest
```

Published with the permission of Yardstick Technologies LLC and listed on their
[download page](https://yardstickhome.com/download/). **This is a community image, not an
official one, hence the name.** For problems with the container, open an issue here; for problems with
Yardstick itself, use [their support](https://yardstickhome.com/support/).

## Quick start

```bash
docker run -d --name yardstick --restart unless-stopped \
  -p 8477:8477 -e TZ=America/New_York \
  -v yardstick-data:/var/lib/yardstick \
  ghcr.io/depasseg/yardstick-community:latest
```

Open `http://<host>:8477`, sign in to your Yarbo account, and activate or start your licence.
A Compose file is in [`examples/docker-compose.yaml`](examples/docker-compose.yaml) and a
Kubernetes manifest in [`examples/kubernetes.yaml`](examples/kubernetes.yaml).

## What you need to know

| | |
| --- | --- |
| **Port** | `8477` (plain HTTP). Yardstick also opens `8478` for its own TLS address; you don't need it behind a reverse proxy. |
| **Data** | `/var/lib/yardstick` holds everything: the SQLite database, `config.json` (your licence, Yarbo tokens, settings), TLS keys. **Back it up.** Use a volume or a local disk; avoid NFS for SQLite. |
| **User** | Runs as uid/gid `1000`, not root. If you bind-mount a host folder, `chown 1000:1000` it. |
| **Licence** | Yardstick licences one activation per "computer", which it ties to an install id in `config.json`, not to the hostname. Keep the data volume and the seat follows the container across restarts, upgrades and hosts. |
| **Robot access** | Through your signed-in Yarbo account (cloud). No special network setup, no host networking needed. |
| **Memory** | Grows slowly while recording; allow 1–2 GB. |
| **Stopping** | The image stops with `SIGINT`, which closes the database cleanly. Give it 30 s (`docker stop -t 30`). |
| **Updates** | Pull a newer image tag; your data stays on the volume. Yardstick's built-in updater doesn't apply here (the image is read-only); the image sets `YARDSTICK_CONTAINER=1`, which newer Yardstick versions read to point you at the image instead of an Update button. |
| **Restores** | Yardstick only accepts a backup restore while the robot is docked and idle, and the restored history appears after a restart. |

### Home Assistant

The [Yardstick integration for Home Assistant](https://github.com/yardstickhome/yardstick)
talks plain HTTP to port 8477. It discovers Yardstick by mDNS, which doesn't cross out of a
container's bridge network, so add it by hand: Settings → Devices & services → Add integration
→ Yardstick → your host's IP and port `8477`. (Or run with `network_mode: host` on Linux.)

### Reverse proxy

Yardstick has no login by default and can drive the robot, so if you expose it beyond your
LAN, put it behind a proxy with authentication, or turn on its own login in Settings. It works
behind Traefik, Caddy, nginx, Envoy and friends with nothing special.

## How the image is built and updated

Yardstick releases often. [`build.yaml`](.github/workflows/build.yaml) runs every 6 hours:
it reads the vendor's signed release list (`yardstickhome.com/release/latest.json`), and if
`ghcr.io/depasseg/yardstick-community:<version>` doesn't exist yet, builds the
[Dockerfile](Dockerfile) for amd64 and arm64 and pushes one multi-arch tag. So a new tag appears
within a few hours of each release, and `latest` follows.

What makes a build trustworthy:
- The `.deb` is downloaded from the URL in the vendor's release list, and its **SHA-256 and
  Ed25519 signature are checked** against the list and Yardstick's release-signing key (the same
  key Yardstick itself checks updates with) before anything is unpacked; the build fails on a
  mismatch. The hashes are also recorded on the image (labels `io.yardstick.deb.sha256.amd64` / `.arm64`).
- The Debian base image is **pinned by digest** (Renovate bumps it), so a rebuild of the same
  commit produces the same image.
- Every build is **scanned with Trivy** before it is pushed: HIGH and CRITICAL findings go to
  this repository's Security tab, and a CRITICAL one with a fix available stops the push. (Trivy
  sees the Debian packages and the libraries Yardstick bundles; it can't audit the vendor's own
  code, which is what the signature check is for.)
- Each pushed image is **signed with Sigstore cosign** (keyless: the signature is tied to this
  repository's workflow, not to a key anyone holds) and recorded in the public Rekor log. Verify
  that an image really came from here before you run it:
  ```bash
  cosign verify ghcr.io/depasseg/yardstick-community:latest \
    --certificate-identity-regexp '^https://github.com/depasseg/yardstick-community/' \
    --certificate-oidc-issuer https://token.actions.githubusercontent.com
  ```
- The package is unpacked as-is; nothing inside is modified. Compare the image's `/opt/yardstick`
  with your own `.deb` if you like.

Tools such as Renovate, Watchtower or Diun can follow the tags for you.

### Build it yourself

```bash
docker build -t yardstick .                                   # the vendor's current release, your CPU's architecture
docker build --build-arg YARDSTICK_VERSION=1.2.8 -t yardstick:1.2.8 .   # must be that version
docker buildx build --platform linux/amd64,linux/arm64 -t yardstick .     # both at once (needs QEMU)
```

## Licence

The files in this repository are MIT. The Yardstick software inside the image is proprietary,
Copyright Yardstick Technologies LLC, under [its EULA](https://yardstickhome.com) (a copy is
in the image at `/usr/share/doc/yardstick/EULA.txt`). You still need your own Yardstick licence.
