#!/bin/bash

# Build (and optionally push) the rootless-sysd image with Podman.
# Mirrors the privileged variant's build.bash but uses podman instead of
# docker/buildx.

DOCKER_HUB_USER="bisos"
IMAGE="deb12-rootless-sysd-vnc-xfce"
TAG="1"
PLATFORMS=linux/amd64,linux/arm64

# Confined base image this image is FROM, and where to build it if missing.
# These images are local-only (not fetched from DockerHub), so build.bash
# resolves the base itself: if it is not already in podman's store, build it
# from the confined image directory before building this image.
BASE_IMAGE="bisos/deb12-fresh-vnc-xfce:1.21"
BASE_CONTEXT="../../../../confined/vnc/xfce/bisos_deb12-fresh"

# Build-time isolation. On some rootless hosts, buildah's default per-RUN
# container/scope creation fails with:
#   sd-bus call: ... org.freedesktop.systemd1 ... Input/output error
# even though `podman run` works fine. --isolation=chroot runs each RUN step
# in a chroot instead, sidestepping the transient-scope path. Resulting image
# layers are identical. Runtime (run.bash) still uses the systemd cgroup
# manager --- this flag only affects BUILD.
ISOLATION="--isolation=chroot"

LOCAL_BUILD=0
getopts 'd' opt 2> /dev/null
if [ "${opt:-}" == 'd' ]; then
  LOCAL_BUILD=1
fi

FULL_IMAGE_NAME=$DOCKER_HUB_USER/$IMAGE:$TAG
echo
echo "Building image: $IMAGE"
echo "      With tag: $TAG"
if [ $LOCAL_BUILD == 1 ]; then
  echo "Using Builder: building locally (podman build)"
else
  echo " For platforms: $PLATFORMS"
  echo "    Pushing to: $DOCKER_HUB_USER (podman manifest)"
fi
echo "     Full name: $FULL_IMAGE_NAME"
echo

# Ensure the confined base image is available in podman's store; build it
# locally from the confined dir if not. (Local-only: we do not pull it.)
if ! podman image exists "$BASE_IMAGE"; then
  echo "Base image $BASE_IMAGE not found in podman's store."
  if [ -f "$BASE_CONTEXT/Dockerfile" ]; then
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

if [ $LOCAL_BUILD == 1 ]; then
  podman build $ISOLATION -t "$FULL_IMAGE_NAME" .
else
  # Multi-arch via a manifest list, then push.
  podman manifest rm "$FULL_IMAGE_NAME" 2>/dev/null || true
  podman build $ISOLATION --platform "$PLATFORMS" --manifest "$FULL_IMAGE_NAME" .
  podman manifest push --all "$FULL_IMAGE_NAME" "docker://docker.io/$FULL_IMAGE_NAME"
fi
