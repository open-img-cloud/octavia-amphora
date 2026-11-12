<p align="center">
  <a href="https://openimages.cloud/images/octavia-amphora/">
    <img src="https://openimages.cloud/img/og/octavia-amphora.png" alt="Octavia amphora image for OpenStack" width="720">
  </a>
</p>

<p align="center">
  <a href="https://openimages.cloud/images/octavia-amphora/"><img alt="Latest version" src="https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fimages.openimages.cloud%2Foctavia-amphora%2Flatest%2FMANIFEST.json&query=%24.version&label=latest&color=2459c4&cacheSeconds=3600"></a>
  <a href="https://github.com/open-img-cloud/octavia-amphora/actions/workflows/release.yml"><img alt="Release" src="https://github.com/open-img-cloud/octavia-amphora/actions/workflows/release.yml/badge.svg"></a>
  <a href="https://openimages.cloud/verify/"><img alt="Signed with Sigstore cosign" src="https://img.shields.io/badge/signed-Sigstore%20cosign-2459c4"></a>
  <a href="LICENSE"><img alt="License GPL-2.0" src="https://img.shields.io/badge/license-GPL--2.0-555"></a>
</p>

<p align="center">
  <a href="https://openimages.cloud/images/octavia-amphora/"><b>Catalog page</b></a> ·
  <a href="https://images.openimages.cloud/octavia-amphora/latest/">Download</a> ·
  <a href="https://openimages.cloud/verify/">Verify</a> ·
  <a href="https://github.com/open-img-cloud/docs">Documentation</a> ·
  <a href="https://github.com/open-img-cloud/octavia-amphora/issues">Report an issue</a>
</p>

Octavia amphora image (qcow2) for **OpenStack**: the `amphora-haproxy` image that
[Octavia](https://docs.openstack.org/octavia/latest/) boots for each load balancer, built per
OpenStack series with Octavia's own
[`diskimage-create`](https://opendev.org/openstack/octavia/src/branch/master/diskimage-create)
and signed with Sigstore cosign, like every [openimages.cloud](https://openimages.cloud) image.
It is an **OpenStack control plane component**: Octavia boots it, tenants never do.

## At a glance

| | |
|---|---|
| **Upstream** | [`openstack/octavia`](https://opendev.org/openstack/octavia) `diskimage-create.sh` at `stable/<series>` (or `unmaintained/<series>` once OpenStack retired the branch), with the matching `openstack/requirements` upper-constraints |
| **Base** | Ubuntu minimal 24.04 (noble), built with [diskimage-builder](https://docs.openstack.org/diskimage-builder/) |
| **Consumer** | The Octavia service, through a Glance image tag (`amphora`) |
| **Format** | qcow2, x86_64, `amphora-<series>-amd64-haproxy.qcow2` |
| **Version** | OpenStack series, e.g. `2026.1`; one image per series, older series stay published |

| OpenStack series | Codename | Octavia branch | Published |
|---|---|---|---|
| 2025.1 | Epoxy | unmaintained/2025.1 | yes |
| 2025.2 | Flamingo | stable/2025.2 | yes |
| 2026.1 | Gazpacho | stable/2026.1 | yes, `latest/` |

## Quick start

```sh
# Latest series and its file name, from the signed manifest
M=https://images.openimages.cloud/octavia-amphora/latest/MANIFEST.json
V=$(curl -fsS $M | jq -r .version); F=$(curl -fsS $M | jq -r .filename)
curl -fLO https://images.openimages.cloud/octavia-amphora/$V/$F
```

Use the image of your Octavia series: replace `latest/` with the series (e.g. `2025.2/`) and
the file name follows the same pattern, `amphora-<series>-amd64-haproxy.qcow2`.

<details>
<summary><b>OpenStack (Octavia operators)</b></summary>

Upload it to Glance with the tag Octavia looks up:

```sh
openstack image create --disk-format qcow2 --container-format bare \
  --tag amphora \
  --file "$F" "amphora-$V-amd64-haproxy"
```

Octavia picks the newest image carrying its amphora tag (`amp_image_tag` in `octavia.conf`,
`amphora` here) when it creates an amphora. To move existing load balancers to the new image:

```sh
openstack loadbalancer failover <lb_id>
```

</details>

<details>
<summary><b>Verify the signature</b></summary>

```sh
curl -fLO https://images.openimages.cloud/octavia-amphora/$V/$F.bundle
cosign verify-blob "$F" --bundle "$F.bundle" \
  --certificate-identity-regexp '^https://github.com/open-img-cloud/\.github/\.github/workflows/build-(libguestfs|dib|nix-flake|freebsd)-image\.yml@' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

The certificate identity is the shared DIB build workflow; `MANIFEST.json` ties the file to
this repository's commit and build run.

</details>

## What this image is

The image is what Octavia's `diskimage-create.sh` produces for the series, with its default
`amphora-agent` and HAProxy elements, Ubuntu minimal noble, a 2 GB disk and the `ConfigDrive`
cloud-init datasource. The build only adds what keeps older series rebuildable:

- when `stable/<series>` is gone upstream, it builds from `unmaintained/<series>` and points
  `octavia-lib` at the same branch;
- `gpgv`, `gnupg2` and `ca-certificates` are included in the debootstrap base, which the
  in-chroot `apt-get update` needs.

Unlike the general-purpose images, it gets no openimages.cloud cloud-init policy: the
amphora agent consumes the configuration Octavia injects.

## How it is validated

This image is **not boot-tested** by openimages.cloud: an amphora only works inside an Octavia
deployment (its own network namespace, configuration and certificates pushed by the
controller), so the shared OpenStack runtime contract does not apply. Each release is:

- built from the pinned Octavia branch and upper-constraints, then checked to exist;
- checksummed and signed with Sigstore cosign (keyless);
- validated after publication from the CDN: `MANIFEST.json` and its required keys, sidecar
  files, cache headers, size limit, and `cosign verify-blob` on the downloaded file.

The functional check is Octavia's own amphora health monitoring once the image is deployed.

## How releases happen

There is no upstream watcher here: OpenStack ships a series every six months on a known
schedule.

1. A pull request bumps [`VERSION`](VERSION) to the new OpenStack series.
2. Merging it is all it takes: `auto-release.yml` tags `v<VERSION>` and starts `release.yml`,
   which builds, signs and publishes the image, then moves `latest/` to it.
3. An older series can be rebuilt with `release.yml` (`workflow_dispatch`, `version` input):
   `latest/` only follows the newest series. `sync-latest.yml` points `latest/` to an already
   published series without rebuilding.

The build runs `build/dib-build.sh` in a privileged `ubuntu:24.04` container on a
GitHub-hosted runner (debootstrap needs full root capabilities). That container is not
signed by this project, so the builder signature check of the other images is off here.

This repository only holds what is specific to the amphora: [`VERSION`](VERSION),
[`build/dib-build.sh`](build/dib-build.sh) and thin workflows calling the shared pipeline in
[`open-img-cloud/.github`](https://github.com/open-img-cloud/.github).

## License

The build tooling in this repository is under [GPL-2.0](LICENSE). The image content keeps its
own licenses (Octavia and diskimage-builder are Apache-2.0, Ubuntu packages under their
respective licenses). OpenStack is a trademark of the Open Infrastructure Foundation; this
project is not affiliated with it.
