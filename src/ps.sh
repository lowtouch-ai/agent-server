#!/bin/bash
source ../init.sh

if [ "$1" == "-a" ]; then
	sudo docker ps -a
else
	sudo docker ps -a | grep "$CONTAINER"
fi
