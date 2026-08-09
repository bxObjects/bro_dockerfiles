#!/bin/bash

# Build (and optionally push) the rootless-sysd image with Podman.
# Mirrors the privileged variant's build.bash but uses podman instead of
# docker/buildx.

DOCKER_HUB_USER="bisos"
IMAGE="deb13-rootless-sysd-vnc-xfce"
TAG="1"
PLATFORMS=linux/amd64,linux/arm64

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

# NOTE: The base image (bisos/deb13-fresh-vnc-xfce) must be built and
# available locally or on DockerHub before building this image.

if [ $LOCAL_BUILD == 1 ]; then
  podman build -t "$FULL_IMAGE_NAME" .
else
  # Multi-arch via a manifest list, then push.
  podman manifest rm "$FULL_IMAGE_NAME" 2>/dev/null || true
  podman build --platform "$PLATFORMS" --manifest "$FULL_IMAGE_NAME" .
  podman manifest push --all "$FULL_IMAGE_NAME" "docker://docker.io/$FULL_IMAGE_NAME"
fi
