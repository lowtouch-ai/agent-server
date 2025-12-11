#!/bin/bash 

if [ "${ENABLE_FLUENTD}" != "0" ]; then
    FLU=$(curl -sL -o /dev/null -w "%{http_code}" http://localhost:24220/api/plugins.json)
    i=1
    while [ "$FLU" != "200" ];
    do
        if [ $i -le 12 ]; then
            FLU=$(curl -sL -o /dev/null -w "%{http_code}" http://localhost:24220/api/plugins.json)
            echo "$(date +%Y%m%d-%H%M%S) Waiting for the fluentd to come up..."
            sleep 5
            i=$((i + 1))
        else
            echo "$(date +%Y%m%d-%H%M%S) WARN: Fluentd check timeout... exiting"
            break
        fi
    done
else
    echo "$(date +%Y%m%d-%H%M%S) INFO: Fluentd is disabled, skipping check..."
fi

if env |grep "VAULT:" > /dev/null 2>&1
then
   c=1
   mc=180
   while ! curl -k -o /dev/null -s -w "%{http_code}\n" -k $VAULT_ADDR/v1/sys/health|grep "200"> /dev/null 2>&1;do
   echo "$(date +%Y%m%d-%H%M%S) waiting for $VAULT_ADDR..."
   sleep 1
   c=`expr $c + 1`
   if [ $c -gt $mc ];then
      echo "$(date +%Y%m%d-%H%M%S) FATAL: vault timeout... exiting"
      exit 1
   fi;done
   if [[ -z "${VAULT_GET_ADDR}" ]]; then
	   VAULT_GET_ADDR=$(echo $VAULT_ADDR|awk -F ':' '{print $1":"$2}' |sed 's/https/http/g')
   fi
   if [[ ! -z "${VAULT_API_ADDR}" ]]; then
	   VAULT_ADDR=${VAULT_API_ADDR}
   fi
   source <(curl -s $VAULT_GET_ADDR/get_secret.sh)
fi

echo "$(date +%Y%m%d-%H%M%S) INFO Starting redis-server..."

#exec /usr/local/bin/docker-entrypoint.sh redis-server 
exec redis-server /usr/local/etc/redis/redis.conf
