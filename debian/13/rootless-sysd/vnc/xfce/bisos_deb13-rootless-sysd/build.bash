#!/bin/bash
#
# Build the deb13 rootless-sysd (bisos_deb13-rootless-sysd) image with podman.
#
# STANDALONE PATH. Needs nothing but podman --- no BISOS, no pip install.
# Permanent peer of ./podmanProc.spcs, kept at parity with it.
# See <<BashPathParity>> in ../../../../../../AI-WorkPlan.org
#
# NOTE: rootless podman requires a cgroup-v2 host with controller delegation.
# The old RedHat VMs cannot run podman at all, so this leaf is NOT part of the
# standalone path's critical use case --- the docker leaves (confined,
# privileged) are. Kept current for consistency.
#
# Usage:
#   ./build.bash            # local build (DEFAULT)
#   ./build.bash -n         # local build, bypass the layer cache
#   ./build.bash -u         # local build, then also push the DockerHub image
#   ./build.bash -d         # accepted, no-op --- local is the default now

# --- Local image name -------------------------------------------------------
# MUST match what bisos.dockerProc derives from this leaf's path
# (paramsFromPlantPath -> imageName:latest). run.bash and podmanProc.spcs both
# expect this name.
LOCAL_IMAGE="bisos_deb13-rootless-sysd"
LOCAL_TAG="latest"

# The confined image this one is FROM (see Dockerfile). Local-only: not pulled.
# If it is missing from podman's store we build it from the confined leaf.
BASE_IMAGE="bisos_deb13-fresh:latest"
BASE_CONTEXT="../../../../confined/vnc/xfce/bisos_deb13-fresh"

# --- DockerHub name ---------------------------------------------------------
# Used ONLY by -u (upload). Irrelevant to a local build.
DOCKER_HUB_USER="bisos"
HUB_IMAGE="deb13-rootless-sysd-vnc-xfce"
HUB_TAG="1"
PLATFORMS=linux/amd64,linux/arm64

# Build-time isolation. On some rootless hosts, buildah's default per-RUN
# container/scope creation fails with:
#   sd-bus call: ... org.freedesktop.systemd1 ... Input/output error
# even though `podman run` works fine. --isolation=chroot runs each RUN step
# in a chroot instead, sidestepping the transient-scope path. Resulting image
# layers are identical. Runtime (run.bash) still uses the systemd cgroup
# manager --- this flag only affects BUILD.
ISOLATION="--isolation=chroot"

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
FULL_HUB_NAME="$DOCKER_HUB_USER/$HUB_IMAGE:$HUB_TAG"

echo
echo "Building image: $FULL_LOCAL_NAME  (local, podman)"
echo "          From: $BASE_IMAGE"
if [ $UPLOAD == 1 ]; then
  echo "     Uploading: $FULL_HUB_NAME"
  echo " For platforms: $PLATFORMS"
else
  echo "     Uploading: no (use -u to push to DockerHub)"
fi
[ -n "$NO_CACHE" ] && echo "      No cache: yes"
echo

# --- Ensure the confined base image is in podman's store --------------------
if ! podman image exists "$BASE_IMAGE"; then
  echo "Base image $BASE_IMAGE not found in podman's store."
  if [ -f "$BASE_CONTEXT/Dockerfile" ]; then
    # The confined Dockerfile does "COPY ./raw-bisos ...", so the payload must
    # be in that build context first. Mirrors the confined leaf's build.bash.
    rawBisosDir="../../../../../../common/raw-bisos"
    if [ -d "$BASE_CONTEXT/$rawBisosDir" ]; then
      rm -rf "$BASE_CONTEXT/raw-bisos"
      cp -r "$BASE_CONTEXT/$rawBisosDir" "$BASE_CONTEXT/raw-bisos" \
        && echo "  Ran:: cp -r <common/raw-bisos> $BASE_CONTEXT/raw-bisos"
    fi
    echo "Building it from $BASE_CONTEXT ..."
    podman build $ISOLATION -t "$BASE_IMAGE" "$BASE_CONTEXT" || {
      echo "ERROR: base image build failed." >&2; exit 1; }
  else
    echo "ERROR: base build context not found at $BASE_CONTEXT" >&2
    exit 1
  fi
else
  echo "Base image present: $BASE_IMAGE"
fi
echo

# --- Build ------------------------------------------------------------------
podman build $ISOLATION $NO_CACHE -t "$FULL_LOCAL_NAME" . || exit 1

if [ $UPLOAD == 1 ]; then
  # Multi-arch via a manifest list, then push.
  podman manifest rm "$FULL_HUB_NAME" 2>/dev/null || true
  podman build $ISOLATION $NO_CACHE --platform "$PLATFORMS" --manifest "$FULL_HUB_NAME" . || exit 1
  podman manifest push --all "$FULL_HUB_NAME" "docker://docker.io/$FULL_HUB_NAME" || exit 1
  echo "  Pushed:: $FULL_HUB_NAME"
fi
