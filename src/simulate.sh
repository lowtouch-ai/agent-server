#!/bin/bash
source ../init.sh
docker exec -it engine python /appz/scripts/simulate.py $@
