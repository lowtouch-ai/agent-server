#!/bin/bash
YAML_FILE=/appz/scripts/mongo_contents/setup.yaml
echo "Waiting for MongoDB to be up and running with auth enabled..."
sleep 60

if env | grep "VAULT:" >/dev/null 2>&1; then
    c=1
    mc=180
    while ! curl -k -o /dev/null -s -w "%{http_code}\n" -k $VAULT_ADDR/v1/sys/health | grep "200" >/dev/null 2>&1; do
        echo "waiting for $VAULT_ADDR..."
        sleep 1
        c=$(expr $c + 1)
        if [ $c -gt $mc ]; then
            echo "FATAL: vault timeout... exiting"
            exit 1
        fi
    done
    VAULT_GET_ADDR=$(echo $VAULT_ADDR | awk -F ':' '{print $1":"$2}' | sed 's/https/http/g')
    source <(curl -s $VAULT_GET_ADDR/get_secret.sh)
fi

if [ ${REPLICATION:-0} -gt 1 ] && [ ${AUTH_ENABLE:-0} -eq 1 ]; then
    echo "Mongo Replication Mode Enabled"

    maxcounter=90
    counter=1
    while ! mongosh -u $DB_USER_ADMIN -p $DB_USER_ADMIN_PASSWORD --eval "rs.status()" | grep -i PRIMARY >/dev/null 2>&1; do
        echo "waiting for mongo Primary..."
        sleep 1
        counter=$(expr $counter + 1)
        if [ $counter -gt $maxcounter ]; then
            echo >&2 "We have been waiting for primary server too long; failing."
            exit 1
        fi
    done

    if [ "$?" -eq 0 ] && [ -f "$YAML_FILE" ]; then
        echo "mongo started successfully"
        echo "Found setup.yaml"

        echo "Setting profiling level to 2 for the '$MONGO_DATABASE' database..."
        mongosh --username "$MONGO_USER" --password "$MONGO_USER_PASSWORD" --authenticationDatabase "$MONGO_DATABASE" <<EOF
use $MONGO_DATABASE;
db.setProfilingLevel(2);
EOF
        echo "Profiling has been set for the '$MONGO_DATABASE' database."

        if [[ $(crontab -l | grep "/appz/scripts/log_profiling.sh") ]]; then
            echo "$(date +%Y%m%d-%H%M%S) INFO Cron job for log_profiling.sh already exists"
        else
            (crontab -l | { cat; echo "* * * * * /usr/bin/supervisorctl start log_profiling"; }) | crontab -
            echo "$(date +%Y%m%d-%H%M%S) INFO Cron job for log_profiling.sh added"
        fi
    fi
else
    echo "Mongo started successfully"
    echo "No setup.yaml found for running the script, Skipping..."
fi
