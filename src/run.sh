#!/usr/bin/env bash

if [ -f ~/.appz/init.conf ]; then
    echo "sourcing ~/.appz/init.conf"
    source ~/.appz/init.conf
fi

if [ -f ~/.appz/custom.conf ]; then
    echo "sourcing ~/.appz/custom.conf"
    source ~/.appz/custom.conf
fi

source ../init.sh

[ -n "$APPZ_DEV_MODE" ] && APPZ_DEV_MODE="-e APPZ_DEV_MODE=$APPZ_DEV_MODE" && echo APPZ_DEV_MODE is ON
echo APPZ_ENV: ${APPZ_ENV}, APPZ_ENV_LOWERCASE: ${APPZ_ENV_LOWERCASE}
echo APP_ID: ${APP_ID}
echo VERSION: ${VERSION}
echo TAG: ${TAG}

#
# Defaults
#



#
# Arguments
#
CLEARDATA=0
POSITIONAL=()
while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    --cleardata)
    CLEARDATA=1
    shift # past argument
    ;;
esac
done
set -- "${POSITIONAL[@]}" # restore positional parameters

#
# Files loader
#

for FILE_TYPE in "push" "options" "ports" "vols" "links" "params" "env" "resources" "secops"
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

if ! echo "$OPTIONS" | grep -q -- "--hostname"; then
    OPTIONS="$OPTIONS --hostname=${CONTAINER} "
fi

OPTIONS="-d $OPTIONS"

#
# Print loaded values
#

echo Options: ${OPTIONS}
echo Ports: ${PORTS}
echo Volumes: ${VOLS}
echo Links: ${LINKS}
echo Params: ${PARAMS}
echo Env: ${ENV}
echo Resources: ${RESOURCES}
echo Secops: ${SECOPS}
echo "------------------"
echo CLEARDATA: ${CLEARDATA}

APPZ_STACK="-e APPZ_STACK=$PROJECT"

if [[ "$TAG" != "" ]]; then
	APPZ_VERSION="-e APPZ_VERSION=$TAG"
fi

if [[ "$APPZ_NOTIFY_EMAIL_OVERRIDE" != "" ]]; then
	APPZ_NOTIFY_EMAIL_OVERRIDE="-e APPZ_NOTIFY_EMAIL_OVERRIDE=${APPZ_NOTIFY_EMAIL_OVERRIDE}"
fi

echo "APPZ_NOTIFY_EMAIL_OVERRIDE=$APPZ_NOTIFY_EMAIL_OVERRIDE"

if [[ "$APPZ_USE_HTTP_PROXY" != "" ]]; then
	APPZ_USE_HTTP_PROXY="-e APPZ_USE_HTTP_PROXY=${APPZ_USE_HTTP_PROXY}"
fi

if [[ "$APPZ_USE_HTTPS_PROXY" != "" ]]; then
	APPZ_USE_HTTPS_PROXY="-e APPZ_USE_HTTPS_PROXY=${APPZ_USE_HTTPS_PROXY}"
fi

if [[ -e "run.sh" ]]; then
   echo "running ./run.sh"
   chmod +x ./run.sh && source ./run.sh
   exit
fi

APPZ_VOLUMES_DIR=${APPZ_VOLUMES_DIR:-/home/appz/volumes}
APPZ_BACKUP_DIR=${APPZ_BACKUP_DIR:-/home/appz/volumes}

echo APPZ_VOLUMES_DIR: ${APPZ_VOLUMES_DIR}
echo APPZ_BACKUP_DIR: ${APPZ_BACKUP_DIR}

sudo mkdir -p ${APPZ_VOLUMES_DIR}/${PROJECT}/home \
   && sudo mkdir -p ${APPZ_VOLUMES_DIR}/${PROJECT}/cache \
   && sudo mkdir -p ${APPZ_VOLUMES_DIR}/${PROJECT}/data \
   && sudo mkdir -p ${APPZ_VOLUMES_DIR}/${PROJECT}/log \
   && sudo mkdir -p ${APPZ_BACKUP_DIR}/${PROJECT}/backup \
   && sudo mkdir -p ${APPZ_VOLUMES_DIR}/common/keys

if [[ "$CLEARDATA" == "1" ]]; then
	echo "******** clearing data. confirm by typing CLEARDATA ********"
	read CLEARDATA
	if [[ "$CLEARDATA" == "CLEARDATA" ]]; then
		echo "******** clearing data. !!! CONFIRMED !!! ********"
		
		sudo rm -rfv ${APPZ_VOLUMES_DIR}/${PROJECT}/home/*
		sudo find ${APPZ_VOLUMES_DIR}/${PROJECT}/home -type f -exec rm -fv {} \;
		
	   	sudo rm -rfv ${APPZ_VOLUMES_DIR}/${PROJECT}/cache/*
		sudo find ${APPZ_VOLUMES_DIR}/${PROJECT}/cache -type f -exec rm -fv {} \;
		
	   	sudo rm -rfv ${APPZ_VOLUMES_DIR}/${PROJECT}/data/*
		sudo find ${APPZ_VOLUMES_DIR}/${PROJECT}/data -type f -exec rm -fv {} \;

	   	sudo rm -rfv ${APPZ_VOLUMES_DIR}/${PROJECT}/log/*
		sudo find ${APPZ_VOLUMES_DIR}/${PROJECT}/log -type f -exec rm -fv {} \;
		
	   	sudo rm -rfv ${APPZ_BACKUP_DIR}/${PROJECT}/backup/*
		sudo find ${APPZ_BACKUP_DIR}/${PROJECT}/backup -type f -exec rm -fv {} \;
		
	   	echo "******** clearing data. !!! COMPLETED !!! ********"	
	fi
fi

sudo docker run ${OPTIONS} \
    --name ${CONTAINER} \
    --restart=on-failure:5 \
    ${RESOURCES} \
    ${PORTS} \
    ${SECOPS} \
    -v ${APPZ_VOLUMES_DIR}/${PROJECT}/home:/appz/home:rw \
    -v ${APPZ_VOLUMES_DIR}/${PROJECT}/cache:/appz/cache:rw \
    -v ${APPZ_VOLUMES_DIR}/${PROJECT}/data:/appz/data:rw \
    -v ${APPZ_VOLUMES_DIR}/${PROJECT}/log:/appz/log:rw \
    -v ${APPZ_BACKUP_DIR}/${PROJECT}/backup:/appz/backup:rw \
    -v /var/run/docker.sock:/var/run/docker.sock:rw \
    -v ${APPZ_VOLUMES_DIR}/common/keys:/appz/keys:rw \
    -v $PWD/scripts:/appz/dev:rw \
    -v ${PARENT}:/appz/docker:rw \
    ${VOLS} \
    ${LINKS} \
    ${APPZ_DEV_MODE} \
    ${ENV} \
    ${APPZ_STACK} \
    ${APPZ_USE_HTTP_PROXY} \
    ${APPZ_USE_HTTPS_PROXY} \
    ${APPZ_VERSION} \
    ${APPZ_NOTIFY_EMAIL_OVERRIDE} \
    ${APPZ_HOST_ADD} \
    ${IMAGE} ${PARAMS}

sudo docker ps -n=1 | grep ${CONTAINER}

echo "Container IP: "$(sudo docker inspect -f '{{.NetworkSettings.IPAddress}}' ${CONTAINER})
