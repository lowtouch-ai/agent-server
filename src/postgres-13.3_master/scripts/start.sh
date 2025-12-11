#!/bin/bash

YAML_FILE=/appz/scripts/postgres-contents/setup.yaml
if [ "$?" -eq 0 ] && [ -f "$YAML_FILE" ]; then
        echo "PostgreSQL started successfully"
        echo "Found setup.yaml and proceeds running the script"
else
        echo "PostgreSQL started successfully"
        echo "No setup.yaml found for running the script, Skipping..."
	exit 1
fi

VAULT_GET_ADDR=$(echo $VAULT_ADDR|awk -F ':' '{print $1":"$2}' |sed 's/https/http/g')
source <(curl -s $VAULT_GET_ADDR/get_secret.sh)

maxcounter=90

counter=1
while ! su - postgres -c "psql -c '\list ' " > /dev/null 2>&1 ; do
    sleep 1
    counter=`expr $counter + 1`
    if [ $counter -gt $maxcounter ]; then
        >&2 echo "We have been waiting for PSQL too long already; failing."
        exit 1
    fi;
done

python3 /appz/scripts/activate_postgres.py
if [ "$?" -eq 0 ]; then
	echo "activate_postgres.py script ran successfully"
else
	echo "Some issues with the script encountered"
fi

	
