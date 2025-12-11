#!/bin/bash
source ../init.sh

set -e

if [[ -e "push.conf" ]]; then

   source "push.conf"
   echo App ID: $APP_ID
   echo Version: $VERSION
   echo TAG: $TAG
   if [[ "$INCREMENT" != "N" ]]; then
   	  TAG=$VERSION.`echo "$TAG" | tail -1 | awk '{print $1}' | awk -F"." '{print $3}' | grep -Eo '[0-9]+' | awk '{print $1+1}'`
   fi
   IMAGE_TAG=$TAG
   echo "IMAGE_TAG: "$IMAGE_TAG
   if [[ "$PREFIX" == "Y" ]]; then
      TAG=$CONTAINER-$TAG
   fi      
   echo tagging git with $TAG  
   if [[ "$INCREMENT" != "N" ]]; then
   	  sed -i 's/TAG=.*/TAG='\'"${IMAGE_TAG}"\''/' push.conf
   fi
    
   git config --global credential.helper 'cache --timeout 300'
   git add push.conf
   git commit -m "Tagging version $TAG"
   git tag $TAG
   git push
   git push --tags

   REGISTRY="registry.ecloudcontrol.com"
	
   if [ "$APPZ_USE_REGISTRY" != "" ]; then
      REGISTRY="${APPZ_USE_REGISTRY}"
   fi

   IMAGE2=$CONTAINER:$IMAGE_TAG
	
   echo pushing ${REGISTRY}/appz/$IMAGE2
   sudo docker tag $IMAGE ${REGISTRY}/appz/$IMAGE2
   sudo docker push ${REGISTRY}/appz/$IMAGE2
   
   if [ "$APPZ_USE_DOCKER_IO" == "YES" ]; then
      echo pushing to ecloudcontrol/$IMAGE2
      sudo docker tag $IMAGE ecloudcontrol/$IMAGE2
      sudo docker push ecloudcontrol/$IMAGE2
   fi
   
   
else
   	echo "Can't find push.conf! exiting!!!"	
fi
