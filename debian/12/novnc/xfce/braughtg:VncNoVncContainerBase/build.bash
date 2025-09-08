# Build and push the multi-architectrue images.

# Modify the following variables as appropraite when building new base inmages.
DOCKER_HUB_USER="braughtg"
IMAGE="vnc-novnc-base"
TAG="1.2.1"
PLATFORMS=linux/amd64,linux/arm64

# Check for the local build flag -d
LOCAL_BUILD=0
getopts 'd' opt 2> /dev/null
if [ $opt == 'd' ];
then 
  LOCAL_BUILD=1
fi

# Only check the login and make the builder if we are pushing the images.
if [ $LOCAL_BUILD == 0 ];
then

  # Check that the DockerHub user identified above is logged in.
  LOGGED_IN=$(docker-credential-desktop list | grep "$DOCKER_HUB_USER" | wc -l | cut -f 8 -d ' ')
  if [ "$LOGGED_IN" == "0" ];
  then
    echo "Please log into Docker Hub as $DOCKER_HUB_USER before building images."
    echo "  Use: docker login"
    echo "This allows multi architecture images to be pushed."
    exit -1
  fi

  # Create a builder for this image if it doesn't exist.
  BUILDER_NAME=vncbuilder
  BUILDER=$(docker buildx ls | grep "$BUILDER_NAME" | wc -l | cut -f 8 -d ' ')
  if [ "$BUILDER" == "0" ];
  then
    echo "Making new builder for $BUILDER_NAME images."
    docker buildx create --name $BUILDER_NAME --driver docker-container --bootstrap
  fi

  # Switch to use the builder for this image.
  docker buildx use $BUILDER_NAME
fi

# Print some info on the images
FULL_IMAGE_NAME=$DOCKER_HUB_USER/$IMAGE:$TAG
echo
echo "Buiding image: $IMAGE"
echo "     With tag: $TAG"
if [ $LOCAL_BUILD == 1 ]; 
then 
  echo "Using Builder: building locally"
else
  echo "For platforms: $PLATFORMS"
  echo "Using builder: $BUILDER_NAME"
fi
echo "   Pushing to: $DOCKER_HUB_USER"
echo "    Full name: $FULL_IMAGE_NAME"
echo

if [ $LOCAL_BUILD == 1 ];
then
  docker build  -t $FULL_IMAGE_NAME .
else
  # Build and push the images.
  docker buildx build --platform $PLATFORMS -t $FULL_IMAGE_NAME --push .
fi