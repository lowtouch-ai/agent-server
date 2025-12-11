#!/bin/bash
source ../init.sh

sudo docker exec -it $CONTAINER supervisorctl -i
