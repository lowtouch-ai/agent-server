#!/bin/bash
VAULT_GET_ADDR=$(echo $VAULT_ADDR|awk -F ':' '{print $1":"$2}' |sed 's/https/http/g')
source <(curl -s $VAULT_GET_ADDR/get_secret.sh)
td-agent
