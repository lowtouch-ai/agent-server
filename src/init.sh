#!/usr/bin/env bash

PARENT=`dirname $PWD`
PROJECT=`basename $PWD`
WORKSPACE=`dirname $(dirname $PWD)`
IMAGE=appz/$PROJECT
IMAGE_LATEST=$IMAGE
CONTAINER=$PROJECT

APPZ_ENV_LOWERCASE=$(echo ${APPZ_ENV} | tr '[:upper:]' '[:lower:]')

if [[ -e "pull.conf" ]]; then
   source "pull.conf"
fi

if [[ $PROJECT == *"-"* ]]; then

  IMAGE=`echo $PROJECT | awk -F '-' '{s = "appz/"$1":"$2; print s}'`
  IMAGE_FILE=`echo $PROJECT | awk -F '-' -v home="$(echo $HOME)" -v host="$(hostname)" -v dt="$(date +%Y%m%d-%H%M%S)" '{s = home"/appz/images/appz_"$1"_"$2"."host"-"dt".tar"; print s}'`
  CONTAINER=`echo $PROJECT | awk -F'-|_' '{if ($3 == "") print $1; else print $1"_"$3}'`

  IMAGE_LATEST=$IMAGE
  if [ "$BUILD_NUMBER" != "" ]; then
	IMAGE=$IMAGE.$BUILD_NUMBER
  fi

else
  IMAGE_FILE=`echo $PROJECT | awk -F '-' -v home="$(echo $HOME)" -v host="$(hostname)" -v dt="$(date +%Y%m%d-%H%M%S)" '{s = home"/appz/images/appz_"$1"."host"-"dt".tar"; print s}'`
fi

IMAGE_FOLDER=`dirname ${IMAGE_FILE}`

if [[ $IMAGE == *":"* ]]; then
	TAG=`echo $IMAGE | awk -F ':' '{print $2}'`
fi

echo project:$PROJECT, image:$IMAGE, container:$CONTAINER
