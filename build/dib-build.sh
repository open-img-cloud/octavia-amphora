#!/usr/bin/env bash
# DIB build hook called by the build-dib-image reusable workflow.
# Receives: $1 = output dir, $2 = version (e.g. "2025.2").
# Must produce: $1/amphora-${version}-amd64-haproxy.qcow2
#
# Octavia ships its own `diskimage-create.sh` wrapper around DIB that
# bundles the amphora-agent element + a curated set of dependencies.
# We let it drive the build instead of calling DIB directly because:
#   - the dependency list (jinja2, dib-utils, etc.) is non-trivial and
#     pinned via Octavia's own requirements.txt
#   - the version-aware logic (stable branch checkout, upper-constraints,
#     amphora-agent ref pinning) lives in their tree and would have to
#     be re-implemented if we bypassed it
#
# Container expected: ubuntu:24.04 (the build_container input on
# release.yml is set to that — debootstrap + apt deps are needed for
# the ubuntu-minimal base OS variant). The reusable workflow's default
# stackopshq libguestfs-tools image won't work because it's Rocky-based
# and lacks debootstrap.

set -euo pipefail

OUT_DIR="${1:?usage: dib-build.sh <output-dir> <version>}"
VERSION="${2:?usage: dib-build.sh <output-dir> <version>}"

# --- Defaults overridable via env from the caller workflow -----------
AMP_BASE_OS="${AMP_BASE_OS:-ubuntu-minimal}"   # debian-minimal | ubuntu-minimal | rocky
AMP_RELEASE="${AMP_RELEASE:-noble}"             # codename for AMP_BASE_OS
AMP_ARCH="${AMP_ARCH:-amd64}"
AMP_IMAGE_TYPE="${AMP_IMAGE_TYPE:-qcow2}"
AMP_SIZE_GB="${AMP_SIZE_GB:-2}"
CLOUD_INIT_DATASOURCES="${CLOUD_INIT_DATASOURCES:-ConfigDrive}"
OCTAVIA_REF="${OCTAVIA_REF:-}"   # auto-derived from VERSION if empty

echo "[dib-build] out_dir=$OUT_DIR version=$VERSION"
echo "[dib-build] base_os=$AMP_BASE_OS release=$AMP_RELEASE arch=$AMP_ARCH"

# --- Derive Octavia branch + upper-constraints from the version ------
# VERSION is the OpenStack series (e.g. "2025.2"); we map it to the
# matching stable/X.Y branch on opendev.org/openstack/octavia, and to
# the same-named branch on opendev.org/openstack/requirements (which
# carries the dependency upper-constraints.txt for that release).
VMAJ="$(printf '%s' "$VERSION" | cut -d. -f1)"
VMIN="$(printf '%s' "$VERSION" | cut -d. -f2)"
SERIES="${VMAJ}.${VMIN}"

REF="$OCTAVIA_REF"
USE_DASH_G="0"
if [[ -z "$REF" ]]; then
  REF="stable/${SERIES}"
  USE_DASH_G="1"
elif [[ "$REF" =~ ^stable/[0-9]+\.[0-9]+$ ]]; then
  USE_DASH_G="1"
fi

UPPER_CONSTRAINTS_URL="${UPPER_CONSTRAINTS_URL:-}"
if [[ -z "$UPPER_CONSTRAINTS_URL" ]]; then
  if [[ "$REF" =~ ^stable/[0-9]+\.[0-9]+$ ]]; then
    UPPER_CONSTRAINTS_URL="https://opendev.org/openstack/requirements/raw/branch/${REF}/upper-constraints.txt"
  elif [[ "$REF" =~ ^[0-9a-f]{7,40}$ ]]; then
    UPPER_CONSTRAINTS_URL="https://opendev.org/openstack/requirements/raw/branch/stable/${SERIES}/upper-constraints.txt"
  else
    UPPER_CONSTRAINTS_URL="https://opendev.org/openstack/requirements/raw/tag/${REF}/upper-constraints.txt"
  fi
fi

echo "[dib-build] ref=$REF use_dash_g=$USE_DASH_G upper_constraints=$UPPER_CONSTRAINTS_URL"

# --- Install build prerequisites (Ubuntu container) -----------------
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  qemu-utils git kpartx debootstrap python3-venv python3-pip \
  ca-certificates jq curl xz-utils e2fsprogs sudo

# --- Clone Octavia at the resolved ref ------------------------------
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
git clone --depth 1 --branch "$REF" \
  https://opendev.org/openstack/octavia.git "$work/octavia" 2>/dev/null || {
  # Fallback: shallow clone of HEAD then checkout (covers tags / SHAs
  # that --branch can't resolve directly).
  git clone https://opendev.org/openstack/octavia.git "$work/octavia"
  ( cd "$work/octavia" && git checkout "$REF" )
}

# --- Python venv with Octavia's diskimage-create requirements -------
cd "$work/octavia/diskimage-create"
python3 -m venv .venv
# shellcheck source=/dev/null
. .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
chmod +x ./diskimage-create.sh

# --- Build the amphora image ----------------------------------------
export CLOUD_INIT_DATASOURCES
export DIB_REPOLOCATION_upper_constraints="$UPPER_CONSTRAINTS_URL"

CMD=( ./diskimage-create.sh
      -i "$AMP_BASE_OS"
      -d "$AMP_RELEASE"
      -a "$AMP_ARCH"
      -t "$AMP_IMAGE_TYPE"
      -s "$AMP_SIZE_GB"
      -o "amphora" )
if [[ "$USE_DASH_G" == "1" ]]; then
  CMD+=( -g "$REF" )
fi

echo "[dib-build] running: ${CMD[*]}"
"${CMD[@]}"

# --- Move the produced qcow2 to the workflow's output dir -----------
final="${OUT_DIR}/amphora-${VERSION}-${AMP_ARCH}-haproxy.${AMP_IMAGE_TYPE}"
mv "amphora.${AMP_IMAGE_TYPE}" "$final"
echo "[dib-build] produced $final"
ls -lh "$final"
