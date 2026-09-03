#!/bin/bash
#
# Build the deb12 privileged (bisos_deb12-sysd) image with docker.
#
# STANDALONE PATH. This script needs nothing but docker --- no BISOS, no pip
# install. It is the only way to build this image on hosts where
# bisos.dockerProc cannot be installed (notably the old RedHat VMs). It is a
# permanent peer of ./dockerProc.spcs, not a legacy alternative, and the two
# must be kept at parity. See <<BashPathParity>> in ../../../../../../AI-WorkPlan.org
#
# Usage:
#   ./build.bash            # local build (DEFAULT)
#   ./build.bash -n         # local build, bypass the layer cache
#   ./build.bash -u         # local build, then also push the DockerHub image
#   ./build.bash -u -n      # push, bypassing the layer cache
#   ./build.bash -d         # accepted, no-op --- local is the default now

# --- Local image name -------------------------------------------------------
# MUST match what bisos.dockerProc derives from this leaf's path
# (containerProc_seedInfo.paramsFromPlantPath -> imageName:latest). This leaf's
# docker-compose.yml and docker-compose.cgv1.yml both say
# "image: bisos_deb12-sysd:latest", so this name is what makes the bash path
# and the .spcs path interoperate.
LOCAL_IMAGE="bisos_deb12-sysd"
LOCAL_TAG="latest"

# The confined image this one is FROM (see Dockerfile). Built by the confined
# leaf's own build.bash; not pulled.
BASE_IMAGE="bisos_deb12-fresh:latest"
BASE_LEAF="../../../../confined/vnc/xfce/bisos_deb12-fresh"

# --- DockerHub name ---------------------------------------------------------
# Used ONLY by -u (upload). Irrelevant to a local build.
DOCKER_HUB_USER="bisos"
HUB_IMAGE="deb12-sysd-vnc-xfce"
HUB_TAG="1"
PLATFORMS=linux/amd64,linux/arm64

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
echo "Building image: $FULL_LOCAL_NAME  (local)"
echo "          From: $BASE_IMAGE"
if [ $UPLOAD == 1 ]; then
  echo "     Uploading: $FULL_HUB_NAME"
  echo " For platforms: $PLATFORMS"
else
  echo "     Uploading: no (use -u to push to DockerHub)"
fi
[ -n "$NO_CACHE" ] && echo "      No cache: yes"
echo

# --- Base image must exist locally ------------------------------------------
if ! docker image inspect "$BASE_IMAGE" >/dev/null 2>&1; then
  echo "ERROR: base image $BASE_IMAGE is not in docker's local store." >&2
  echo "       Build the confined leaf first:" >&2
  echo "         ( cd $BASE_LEAF && ./build.bash )" >&2
  exit 1
fi

# --- Build ------------------------------------------------------------------
docker build $NO_CACHE -t "$FULL_LOCAL_NAME" . || exit 1

if [ $UPLOAD == 1 ]; then
  LOGGED_IN=$(docker-credential-desktop list 2>/dev/null | grep -c "$DOCKER_HUB_USER")
  if [ "$LOGGED_IN" == "0" ]; then
    echo "Please log into Docker Hub as $DOCKER_HUB_USER before uploading images." >&2
    echo "  Use: docker login" >&2
    exit 1
  fi

  BUILDER_NAME=vncbuilder
  BUILDER=$(docker buildx ls | grep -c "$BUILDER_NAME")
  if [ "$BUILDER" == "0" ]; then
    echo "Making new builder for $BUILDER_NAME images."
    docker buildx create --name $BUILDER_NAME --driver docker-container --bootstrap
  fi
  docker buildx use $BUILDER_NAME

  docker buildx build $NO_CACHE --platform $PLATFORMS -t "$FULL_HUB_NAME" --push . || exit 1
  echo "  Pushed:: $FULL_HUB_NAME"
fi
