#!/bin/bash
#
# imageBuild.sh --- Build this leaf's image, with docker or podman.
#
# STANDALONE PATH. This script needs nothing but docker (or podman, for the
# rootless-sysd leaves) --- no BISOS, no pip install. It is the only way to
# build these images on hosts where bisos.dockerProc cannot be installed
# (notably the old RedHat VMs). It is a permanent peer of the leaf's
# dockerProc.spcs / podmanProc.spcs, not a legacy alternative, and the two must
# be kept at parity. Its companion for running the image is ./containerManage.sh
# (see ./README.org).
#
# This file is IDENTICAL in every leaf of bro_dockerfiles. Everything it needs
# is derived from the leaf:
#   - The leaf path debian/<release>/<profile>/vnc/xfce/<leafName>/:
#       image name = <leafName>:latest (what bisos.dockerProc's
#                    paramsFromPlantPath derives too);
#       engine     = podman for the rootless-sysd profile, docker otherwise.
#   - The Dockerfile:
#       FROM bisos_<...>:latest  -> a local base image, built by the leaf of
#                                   that name in the same release;
#       COPY ./raw-bisos ...     -> the Raw-BISOS payload is copied in from
#                                   bro_dockerfiles/common/raw-bisos first;
#       LABEL org.bisos.hubImage / org.bisos.hubTag -> the DockerHub name,
#                                   used only by -u.
#
# Usage:
#   ./imageBuild.sh            # local build (DEFAULT)
#   ./imageBuild.sh -n         # local build, bypass the layer cache
#   ./imageBuild.sh -u         # local build, then also push the DockerHub image
#   ./imageBuild.sh -u -n      # push, bypassing the layer cache
#   ./imageBuild.sh -d         # accepted, no-op --- local is the default now

# All paths below are relative to this leaf, wherever the script is run from.
cd "$(dirname "$(readlink -f "$0")")" || exit 1

# --- Refuse to run inside a container ---------------------------------------
# Same heuristics as bisos.dockerProc (containerProc_csu._detectInContainer).
# Images are built on the Container Platform (a host), never from inside a
# container.
inContainerReason() {
  if [ -e /.dockerenv ]; then echo "/.dockerenv exists (docker)"; return 0; fi
  if [ -e /run/.containerenv ]; then echo "/run/.containerenv exists (podman)"; return 0; fi
  local marker
  for marker in docker containerd libpod kubepods lxc; do
    if grep -q "$marker" /proc/1/cgroup 2>/dev/null; then
      echo "/proc/1/cgroup contains '$marker'"; return 0
    fi
  done
  return 1
}
if reason=$(inContainerReason); then
  echo "ERROR: this is running inside a container ($reason)." >&2
  echo "       Build images on the host (the Container Platform), not in a container." >&2
  exit 1
fi

# --- A numeric suffix means a secondary instance ----------------------------
# A leaf named <primary>-<N> (e.g. bisos_deb13-sysd-2) is another instance of
# the image of ../<primary>. It has no image of its own: the image is built in
# the primary leaf only.
LEAF_NAME=$(basename "$PWD")
if [[ $LEAF_NAME =~ ^(.+)-([0-9]+)$ ]]; then
  primaryLeaf="${BASH_REMATCH[1]}"
  echo "$LEAF_NAME is instance ${BASH_REMATCH[2]} of the image of ../$primaryLeaf."
  echo "It has no image of its own."
  echo "That image is built in the primary leaf:"
  echo "  ( cd ../$primaryLeaf && ./imageBuild.sh )"
  exit 0
fi

# --- Facts from the leaf path -----------------------------------------------
# .../debian/<release>/<profile>/vnc/xfce/<leafName>
PROFILE=$(basename "$(readlink -f ../../..)")
case "$PROFILE" in
  confined|privileged) ENGINE="docker" ;;
  rootless-sysd)       ENGINE="podman" ;;
  *)
    echo "ERROR: unexpected leaf path $PWD" >&2
    echo "       (profile segment is '$PROFILE'; expected confined, privileged or rootless-sysd)." >&2
    exit 1
    ;;
esac
RELEASE_DIR="../../../.."

# MUST match what bisos.dockerProc derives from this leaf's path
# (containerProc_seedInfo.paramsFromPlantPath -> imageName:latest), and the
# image: of this leaf's compose files. That is what makes the bash path and the
# .spcs path interoperate.
LOCAL_IMAGE="$LEAF_NAME"
LOCAL_TAG="latest"

# --- Facts from the Dockerfile ----------------------------------------------
if [ ! -f Dockerfile ]; then
  echo "ERROR: no Dockerfile in $PWD." >&2
  exit 1
fi
FROM_IMAGE=$(sed -n 's/^FROM[[:space:]]\{1,\}\([^[:space:]]*\).*/\1/p' Dockerfile | head -1)

# A FROM bisos_* image is local: built by the leaf of that name in this
# release, never pulled. Anything else (debian:13.1) is pulled by the engine.
BASE_IMAGE=""
BASE_LEAF=""
if [[ $FROM_IMAGE == bisos_* ]]; then
  BASE_IMAGE="$FROM_IMAGE"
  baseName="${FROM_IMAGE%%:*}"
  for d in "$RELEASE_DIR"/*/vnc/xfce/"$baseName"; do
    [ -d "$d" ] && BASE_LEAF="$d"
  done
  if [ -z "$BASE_LEAF" ]; then
    echo "ERROR: Dockerfile is FROM $FROM_IMAGE, but no leaf named $baseName exists" >&2
    echo "       under $(readlink -f "$RELEASE_DIR")." >&2
    exit 1
  fi
fi

# needsRawBisos <dir> --- true if <dir>/Dockerfile copies in ./raw-bisos.
needsRawBisos() { grep -Eq '^COPY.*[[:space:]]\./raw-bisos([[:space:]]|$)' "$1/Dockerfile"; }

# labelValue <key> --- the value of <key>="..." on a LABEL line of the Dockerfile.
labelValue() { sed -n "/^LABEL/s/.*[[:space:]]$1=\"\([^\"]*\)\".*/\1/p" Dockerfile | head -1; }

# --- DockerHub name ---------------------------------------------------------
# Used ONLY by -u (upload). Irrelevant to a local build.
HUB_IMAGE=$(labelValue 'org\.bisos\.hubImage')   # e.g. bisos/deb13-sysd-vnc-xfce
HUB_TAG=$(labelValue 'org\.bisos\.hubTag')
DOCKER_HUB_USER="${HUB_IMAGE%%/*}"
PLATFORMS=linux/amd64,linux/arm64

# Build-time isolation for podman. On some rootless hosts, buildah's default
# per-RUN container/scope creation fails with:
#   sd-bus call: ... org.freedesktop.systemd1 ... Input/output error
# even though `podman run` works fine. --isolation=chroot runs each RUN step
# in a chroot instead, sidestepping the transient-scope path. Resulting image
# layers are identical. Runtime still uses the systemd cgroup manager --- this
# flag only affects BUILD. Same as bisos.dockerProc's containerProc_imageBuild.
PODMAN_ISOLATION="--isolation=chroot"

UPLOAD=0
NO_CACHE=""
while getopts 'und' opt 2>/dev/null; do
  case $opt in
    u) UPLOAD=1 ;;
    n) NO_CACHE="--no-cache" ;;
    d) : ;;   # historical "local build" flag; local is the default now
  esac
done

FULL_LOCAL_NAME="$LOCAL_IMAGE:$LOCAL_TAG"
FULL_HUB_NAME="$HUB_IMAGE:$HUB_TAG"

if [ $UPLOAD == 1 ] && { [ -z "$HUB_IMAGE" ] || [ -z "$HUB_TAG" ]; }; then
  echo "ERROR: -u needs the DockerHub name, and the Dockerfile has no" >&2
  echo "       LABEL org.bisos.hubImage=\"...\" org.bisos.hubTag=\"...\"" >&2
  exit 1
fi

if ! command -v "$ENGINE" >/dev/null 2>&1; then
  echo "ERROR: $ENGINE is not installed on this host (this is a $PROFILE leaf)." >&2
  exit 1
fi

echo
echo "Building image: $FULL_LOCAL_NAME  (local, $ENGINE)"
echo "          From: $FROM_IMAGE"
if [ $UPLOAD == 1 ]; then
  echo "     Uploading: $FULL_HUB_NAME"
  echo " For platforms: $PLATFORMS"
else
  echo "     Uploading: no (use -u to push to DockerHub)"
fi
[ -n "$NO_CACHE" ] && echo "      No cache: yes"
echo

# --- Raw-BISOS bootstrap payload --------------------------------------------
# A Dockerfile that does "COPY ./raw-bisos ..." (the confined leaves) needs the
# payload in its build context. There is a single canonical copy at
# bro_dockerfiles/common/raw-bisos; copy it in before building. The .spcs path
# needs this same step (tracked in bisos.dockerProc).
# copyRawBisos <buildContextDir>
copyRawBisos() {
  local ctx="$1"
  local rawBisosDir="$ctx/../../../../../../common/raw-bisos"
  if [ ! -d "$rawBisosDir" ]; then
    echo "  PROBLEM:: Missing Dir: $(readlink -m "$rawBisosDir")" >&2
    return 1
  fi
  # Remove first: "cp -r <dir> ." nests into ./raw-bisos/raw-bisos when
  # ./raw-bisos already exists, so a repeat build would corrupt the context.
  rm -rf "$ctx/raw-bisos"
  cp -r "$rawBisosDir" "$ctx/raw-bisos" || return 1
  echo "  Ran:: rm -rf $ctx/raw-bisos && cp -r <common/raw-bisos> $ctx/raw-bisos"
}

if needsRawBisos .; then
  copyRawBisos . || exit 1
fi

# --- Base image must exist locally ------------------------------------------
if [ -n "$BASE_IMAGE" ]; then
  if [ "$ENGINE" == "docker" ]; then
    if ! docker image inspect "$BASE_IMAGE" >/dev/null 2>&1; then
      echo "ERROR: base image $BASE_IMAGE is not in docker's local store." >&2
      echo "       Build its leaf first:" >&2
      echo "         ( cd $BASE_LEAF && ./imageBuild.sh )" >&2
      exit 1
    fi
  else
    # podman has its own image store, and the base leaf builds with docker.
    # Build the base into podman's store here, from the base leaf's context.
    if podman image exists "$BASE_IMAGE"; then
      echo "Base image present: $BASE_IMAGE"
    else
      echo "Base image $BASE_IMAGE not found in podman's store."
      if needsRawBisos "$BASE_LEAF"; then
        copyRawBisos "$BASE_LEAF" || exit 1
      fi
      echo "Building it from $BASE_LEAF ..."
      podman build $PODMAN_ISOLATION -t "$BASE_IMAGE" "$BASE_LEAF" || {
        echo "ERROR: base image build failed." >&2; exit 1; }
    fi
    echo
  fi
fi

# --- Build ------------------------------------------------------------------
if [ "$ENGINE" == "docker" ]; then
  docker build $NO_CACHE -t "$FULL_LOCAL_NAME" . || exit 1
else
  podman build $PODMAN_ISOLATION $NO_CACHE -t "$FULL_LOCAL_NAME" . || exit 1
fi

if [ $UPLOAD == 1 ]; then
  if [ "$ENGINE" == "docker" ]; then
    # Check that the DockerHub user identified above is logged in.
    LOGGED_IN=$(docker-credential-desktop list 2>/dev/null | grep -c "$DOCKER_HUB_USER")
    if [ "$LOGGED_IN" == "0" ]; then
      echo "Please log into Docker Hub as $DOCKER_HUB_USER before uploading images." >&2
      echo "  Use: docker login" >&2
      exit 1
    fi

    # Create a builder for this image if it doesn't exist.
    BUILDER_NAME=vncbuilder
    BUILDER=$(docker buildx ls | grep -c "$BUILDER_NAME")
    if [ "$BUILDER" == "0" ]; then
      echo "Making new builder for $BUILDER_NAME images."
      docker buildx create --name $BUILDER_NAME --driver docker-container --bootstrap
    fi
    docker buildx use $BUILDER_NAME

    docker buildx build $NO_CACHE --platform $PLATFORMS -t "$FULL_HUB_NAME" --push . || exit 1
  else
    # Multi-arch via a manifest list, then push.
    podman manifest rm "$FULL_HUB_NAME" 2>/dev/null || true
    podman build $PODMAN_ISOLATION $NO_CACHE --platform "$PLATFORMS" --manifest "$FULL_HUB_NAME" . || exit 1
    podman manifest push --all "$FULL_HUB_NAME" "docker://docker.io/$FULL_HUB_NAME" || exit 1
  fi
  echo "  Pushed:: $FULL_HUB_NAME"
fi
