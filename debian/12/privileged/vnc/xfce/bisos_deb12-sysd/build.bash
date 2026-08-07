#!/bin/bash

# Build and push the multi-architecture images.

DOCKER_HUB_USER="bisos"
IMAGE="deb12-sysd-vnc-xfce"
TAG="1"
PLATFORMS=linux/amd64,linux/arm64

LOCAL_BUILD=0
getopts 'd' opt 2> /dev/null
if [ $opt == 'd' ]; then
  LOCAL_BUILD=1
fi

if [ $LOCAL_BUILD == 0 ]; then

  LOGGED_IN=$(docker-credential-desktop list | grep "$DOCKER_HUB_USER" | wc -l | cut -f 8 -d ' ')
  if [ "$LOGGED_IN" == "0" ]; then
    echo "Please log into Docker Hub as $DOCKER_HUB_USER before building images."
    echo "  Use: docker login"
    exit -1
  fi

  BUILDER_NAME=vncbuilder
  BUILDER=$(docker buildx ls | grep "$BUILDER_NAME" | wc -l | cut -f 8 -d ' ')
  if [ "$BUILDER" == "0" ]; then
    echo "Making new builder for $BUILDER_NAME images."
    docker buildx create --name $BUILDER_NAME --driver docker-container --bootstrap
  fi

  docker buildx use $BUILDER_NAME
fi

FULL_IMAGE_NAME=$DOCKER_HUB_USER/$IMAGE:$TAG
echo
echo "Building image: $IMAGE"
echo "      With tag: $TAG"
if [ $LOCAL_BUILD == 1 ]; then
  echo "Using Builder: building locally"
else
  echo " For platforms: $PLATFORMS"
  echo " Using builder: $BUILDER_NAME"
fi
echo "    Pushing to: $DOCKER_HUB_USER"
echo "     Full name: $FULL_IMAGE_NAME"
echo

# NOTE: The base image (bisos/deb12-fresh-vnc-xfce) must be built and
# available locally or on DockerHub before building this image.

if [ $LOCAL_BUILD == 1 ]; then
  docker build -t $FULL_IMAGE_NAME .
else
  docker buildx build --platform $PLATFORMS -t $FULL_IMAGE_NAME --push .
fi
