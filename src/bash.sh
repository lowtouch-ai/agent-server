#!/bin/bash
source ../init.sh

sudo docker exec -it $CONTAINER bash --rcfile /appz/.bashrc -i
