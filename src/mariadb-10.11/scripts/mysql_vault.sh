#!/bin/bash

FLU=$(curl -sL -o /dev/null -w \"%{http_code}\" http://localhost:24220/api/plugins.json)
while [ $FLU != '"200"' ];
do
        FLU=$(curl -sL -o /dev/null -w \"%{http_code}\" http://localhost:24220/api/plugins.json)
        echo "Waiting for the fluentd to come up..."
        sleep 5
done

LOGDATE="`date +%Y_%b_%d_%H:%M:%S`"
OLD_MYSQL_ROOT=$MYSQL_ROOT_PASSWORD
if env |grep "VAULT:" > /dev/null 2>&1
then
   c=1
   mc=180
   while ! curl -k -o /dev/null -s -w "%{http_code}\n" -k $VAULT_ADDR/v1/sys/health|grep "200"> /dev/null 2>&1;do
   echo "waiting for $VAULT_ADDR..."
   sleep 1
   c=`expr $c + 1`
   if [ $c -gt $mc ];then
      echo "FATAL: vault timeout... exiting"
      exit 1
   fi;done
   VAULT_GET_ADDR=$(echo $VAULT_ADDR|awk -F ':' '{print $1":"$2}' |sed 's/https/http/g')
   source <(curl -s $VAULT_GET_ADDR/get_secret.sh)

fi
if [ -z "$MYSQL_ROOT_PASSWORD" ]  || [ "$MYSQL_ROOT_PASSWORD" == "null" ] ; then
   echo "MYSQL_ROOT_PASSWORD value is null or empty"
   exit 1
fi
if [ $MYSQL_ROOT_PASSWORD == $OLD_MYSQL_ROOT ]
then
        echo "MYSQL ROOT PASSWORD NOT FOUND FROM VAULT"
	exit 1
fi
 /usr/local/bin/docker-entrypoint.sh mysqld
exec "$@"

