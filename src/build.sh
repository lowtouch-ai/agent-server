#!/bin/bash
if [ -f ~/.appz/init.conf ]; then
    echo "sourcing ~/.appz/init.conf"
    source ~/.appz/init.conf
fi

if [ -f ~/.appz/custom.conf ]; then
    echo "sourcing ~/.appz/custom.conf"
    source ~/.appz/custom.conf
fi

source ../init.sh

#
# .conf files loader
#

for FILE_TYPE in "build"
do
    APPZ_ENV_FILE="$FILE_TYPE.$APPZ_ENV_LOWERCASE.conf"
    DEFAULT_FILE="$FILE_TYPE.conf"

    if [[ -e ${APPZ_ENV_FILE} ]]; then
        source ${APPZ_ENV_FILE}
    fi
    if [[ ! -e ${APPZ_ENV_FILE} ]] && [[ -e ${DEFAULT_FILE} ]]; then
        source ${DEFAULT_FILE}
    fi
done


if [ "$APPZ_USE_CACHED_BUILD" == "NO" ]; then
	USE_CACHE="--no-cache"
fi

if [ "$APPZ_USE_HTTP_PROXY" != "" ]; then
	APPZ_USE_HTTP_PROXY="--build-arg APPZ_USE_HTTP_PROXY=${APPZ_USE_HTTP_PROXY} --build-arg http_proxy=${APPZ_USE_HTTP_PROXY}"
fi

if [ "$APPZ_USE_HTTPS_PROXY" != "" ]; then
	APPZ_USE_HTTPS_PROXY="--build-arg APPZ_USE_HTTPS_PROXY=${APPZ_USE_HTTPS_PROXY} --build-arg https_proxy=${APPZ_USE_HTTPS_PROXY}"
fi

if [ "$APPZ_HOST_ADD" != "" ]; then
	echo using $APPZ_HOST_ADD
fi

if [ "$SOURCE" != "" ]; then
	if [ ! -d "../../$SOURCE" ]; then
		echo "project $SOURCE missing!"
		exit -1
	fi	
	WEBAPPS_FOLDER=`bash -c "cd webapps; pwd"`
	SOURCE_ZIP="${WEBAPPS_FOLDER}/${SOURCE}.zip"	
	echo "cleaning "${WEBAPPS_FOLDER}
	rm -fv webapps/*
	echo "preparing "${SOURCE_ZIP}" from "$SOURCE
	bash -c "cd ../../ && pwd && zip -r $SOURCE_ZIP $SOURCE"
	echo project archive $SOURCE_ZIP is ready
	ls -lh $SOURCE_ZIP
fi

sudo docker build $APPZ_HOST_ADD $BUILD $APPZ_USE_HTTP_PROXY $APPZ_USE_HTTPS_PROXY -t $IMAGE --force-rm=true --rm=true $USE_CACHE .
