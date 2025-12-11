#!/bin/bash

docker exec -it cassandra cqlsh -k appz --no-color "$@"
