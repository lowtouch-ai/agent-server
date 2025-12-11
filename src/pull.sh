#!/bin/bash
source ../init.sh

set -e

REGISTRY="registry.ecloudcontrol.com"

if [ "$APPZ_USE_REGISTRY" != "" ]; then
	REGISTRY="${APPZ_USE_REGISTRY}"
fi

if [ "$BUILD_NUMBER" == "" ]; then
   echo "BUILD_NUMBER is not defined! Please use pull.conf to define it. exiting!"
   exit
fi


if [ "$APPZ_USE_REGISTRY" = "docker.io" ]; then
	IMAGE_URL=`echo $IMAGE | sed 's+appz+ecloudcontrol+'`
else
	IMAGE_URL=$REGISTRY/$IMAGE
fi
echo "Image url   :" $IMAGE_URL
   
docker pull $IMAGE_URL  
docker tag $IMAGE_URL $IMAGE
docker tag $IMAGE_URL $IMAGE_LATEST
docker images $IMAGE
docker images $IMAGE_LATEST | tail -1
