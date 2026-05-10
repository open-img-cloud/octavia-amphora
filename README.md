<div id="top"></div>

<!-- PROJECT SHIELDS -->
[![Contributors][contributors-shield]][contributors-url]
[![Forks][forks-shield]][forks-url]
[![Stargazers][stars-shield]][stars-url]
[![Issues][issues-shield]][issues-url]
[![GPL-2.0 License][license-shield]][license-url]

<!-- PROJECT LOGO -->
<br />
<div align="center">

<h3 align="center">Octavia Amphora Cloud Images</h3>

  <p align="center">
    Signed Octavia amphora-haproxy images for OpenStack LBaaS, built per
    OpenStack stable release
    <br />
    <br />
    <a href="https://github.com/open-img-cloud/octavia-amphora/issues">Report a bug</a>
    ·
    <a href="https://github.com/open-img-cloud/octavia-amphora/issues">Request a feature</a>
  </p>
</div>

## About

This repo builds **Octavia amphora** images — the qcow2 images deployed
by OpenStack [Octavia LBaaS][octavia] as load-balancer instances. Unlike
the other openimages.cloud repos (alpaquita, alpine, AL2023, …) which
republish OS images for end-users, amphora is an **OpenStack control
plane component**: it's consumed by the Octavia service in your cluster,
not by tenants directly.

The build follows Octavia's own [`diskimage-create`][octavia-dic]
workflow, which wraps [diskimage-builder][dib] with the Octavia-specific
`amphora-agent` element + a curated set of dependencies. We let it
drive the build and republish through the openimages.cloud
signed-release pipeline.

The build pipeline is shared with the rest of [`open-img-cloud`][org]:
this repo only ships the `VERSION`, `build/dib-build.sh`, and a thin
caller workflow that delegates to the reusable `build-dib-image.yml`
in [`open-img-cloud/.github`][shared] (`@main`).

## Versioning

`<version>` is the **OpenStack series** (e.g. `2025.2` for "Flamingo"),
which maps to the matching `stable/X.Y` branch of
`opendev.org/openstack/octavia`. The build pulls Octavia at that branch,
installs its `diskimage-create` requirements via a Python venv, and
runs the script with the corresponding upper-constraints URL from
`opendev.org/openstack/requirements`.

Tag your release as `v<version>` (e.g. `v2025.2`) to publish.

| OpenStack series | Codename  | Octavia branch       |
|------------------|-----------|----------------------|
| 2024.1           | Caracal   | stable/2024.1        |
| 2024.2           | Dalmatian | stable/2024.2        |
| 2025.1           | Epoxy     | stable/2025.1        |
| 2025.2           | Flamingo  | stable/2025.2 ← default |
| 2026.1           | _TBD_     | stable/2026.1        |

## Where to download

Public CDN, served via Cloudflare in front of an R2 bucket (mirror of
the source-of-truth Garage):

| URL pattern                                                                          | Cache policy                  |
|--------------------------------------------------------------------------------------|-------------------------------|
| `https://images.openimages.cloud/octavia-amphora/<version>/<filename>`               | `max-age=31536000, immutable` |
| `https://images.openimages.cloud/octavia-amphora/latest/<filename>`                  | `max-age=300`                 |

Browse: [images.openimages.cloud/octavia-amphora/latest/][latest]

Filename: `amphora-<version>-amd64-haproxy.qcow2` (e.g.
`amphora-2025.2-amd64-haproxy.qcow2`).

## Verify before deploy

cosign 3.x:

```sh
sha256sum -c <filename>.sha256                    # integrity
cosign verify-blob \
    --bundle <filename>.bundle \
    --new-bundle-format \
    --certificate-identity-regexp '^https://github.com/open-img-cloud/\.github/\.github/workflows/build-dib-image\.yml@' \
    --certificate-oidc-issuer https://token.actions.githubusercontent.com \
    <filename>                                     # provenance
```

The certificate identity points at the **reusable** DIB build workflow
in `open-img-cloud/.github` — that's where GitHub's OIDC binds the SAN
for keyless signing. To tie the artifact back to *this* repo's commit,
also check `MANIFEST.json` (commit, build_url, builder digest).

## How to use (Octavia operators)

Once published, point your Octavia controller at the qcow2 in Glance:

```sh
# Pull the qcow2 (replace <V> with the OpenStack series, e.g. 2025.2)
curl -fLO https://images.openimages.cloud/octavia-amphora/<V>/amphora-<V>-amd64-haproxy.qcow2

# Upload to Glance with the amphora tag Octavia looks up
openstack image create \
    --disk-format qcow2 --container-format bare \
    --tag amphora \
    --file amphora-<V>-amd64-haproxy.qcow2 \
    "amphora-<V>-amd64-haproxy"

# Octavia will pick the latest image with the `amphora` tag at next
# load-balancer provisioning. To force migration of existing LBs:
#   openstack loadbalancer failover <lb_id>
```

## Release flow

1. Maintainer bumps `VERSION` to the target OpenStack series (no
   `watch.yml` here — OpenStack ships every 6 months on a known
   schedule, manual bump is fine).
2. Tag `v<version>` triggers `release.yml`, which calls the shared
   `build-dib-image.yml@main` reusable workflow.
3. The reusable workflow runs `build/dib-build.sh` inside an
   `ubuntu:24.04` container with `--privileged` (DIB needs loopback
   mounts for debootstrap).
4. The script clones `opendev.org/openstack/octavia` at
   `stable/<version>`, installs its `diskimage-create/requirements.txt`
   in a venv, then runs `diskimage-create.sh` with the matching
   upper-constraints URL.
5. Output qcow2 is signed (cosign keyless), bundled with MANIFEST,
   uploaded to Garage + R2, and Cloudflare cache for `latest/` is
   purged.

## Repository layout

```
VERSION                          single line, e.g. "2025.2"
build/
  dib-build.sh                   DIB build hook (out_dir as $1, version as $2)
.github/workflows/
  release.yml                    calls build-dib-image.yml on tag push
.gitignore                       repo-local override for global build/ exclusion
LICENSE                          GPL-2.0
```

## Notes vs the OS-image repos

- **No cloud-init policy drop-in.** Amphora isn't bootable by end-users
  — its userdata is consumed by the `amphora-agent` running inside the
  image, not generic cloud-init. The `99_oic-policy.cfg` injection that
  the libguestfs reusable does for OS images is irrelevant here.
- **No smoke test.** Amphora boots into a constrained network namespace
  driven by Octavia; the reusable `build-dib-image.yml` workflow
  deliberately doesn't have a smoke step. Validation happens
  post-deploy via Octavia's own health checks.
- **Build container is `ubuntu:24.04`**, not the stackopshq libguestfs
  image, because the ubuntu-minimal DIB element needs `debootstrap` +
  apt deps. As a consequence `verify_builder: false` — we trust
  Docker Hub's `ubuntu:24.04` here. This may tighten later if we ship
  our own dib-builder image.

## Contributing

Fork, branch, PR. Keep the dib-build script focused on Octavia's
upstream `diskimage-create.sh` invocation; complex env wiring should
move to the workflow inputs rather than be hardcoded.

## License

Distributed under the GPL-2.0 License. See `LICENSE`.

## Contact

Kevin Allioli — kevin@stackops.ch · [@stackopshq](https://twitter.com/stackopshq)

Project: [open-img-cloud/octavia-amphora](https://github.com/open-img-cloud/octavia-amphora)

[octavia]: https://docs.openstack.org/octavia/
[octavia-dic]: https://opendev.org/openstack/octavia/src/branch/master/diskimage-create
[dib]: https://docs.openstack.org/diskimage-builder/
[org]: https://github.com/open-img-cloud
[shared]: https://github.com/open-img-cloud/.github
[latest]: https://images.openimages.cloud/octavia-amphora/latest/

<!-- shields -->
[contributors-shield]: https://img.shields.io/github/contributors/open-img-cloud/octavia-amphora.svg?style=for-the-badge
[contributors-url]: https://github.com/open-img-cloud/octavia-amphora/graphs/contributors
[forks-shield]: https://img.shields.io/github/forks/open-img-cloud/octavia-amphora.svg?style=for-the-badge
[forks-url]: https://github.com/open-img-cloud/octavia-amphora/network/members
[stars-shield]: https://img.shields.io/github/stars/open-img-cloud/octavia-amphora.svg?style=for-the-badge
[stars-url]: https://github.com/open-img-cloud/octavia-amphora/stargazers
[issues-shield]: https://img.shields.io/github/issues/open-img-cloud/octavia-amphora.svg?style=for-the-badge
[issues-url]: https://github.com/open-img-cloud/octavia-amphora/issues
[license-shield]: https://img.shields.io/github/license/open-img-cloud/octavia-amphora.svg?style=for-the-badge
[license-url]: https://github.com/open-img-cloud/octavia-amphora/blob/main/LICENSE
