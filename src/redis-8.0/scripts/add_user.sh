#!/usr/bin/env bash

if env |grep "VAULT:" > /dev/null 2>&1
then
   c=1
   mc=180
   while ! curl -k -o /dev/null -s -w "%{http_code}\n" -k $VAULT_ADDR/v1/sys/health|grep "200"> /dev/null 2>&1;do
   echo "$(date +%Y%m%d-%H%M%S) INFO waiting for $VAULT_ADDR..."
   sleep 1
   c=`expr $c + 1`
   if [ $c -gt $mc ];then
      echo "$(date +%Y%m%d-%H%M%S) ERROR FATAL: vault timeout... exiting"
      exit 1
   fi;done
   VAULT_GET_ADDR=$(echo $VAULT_ADDR|awk -F ':' '{print $1":"$2}' |sed 's/https/http/g')
   source <(curl -s $VAULT_GET_ADDR/get_secret.sh)
fi
AUTH=${AUTH:-False}
until [ "$(redis-cli ping 2>/dev/null|grep -qi 'pong' ;echo $?)" != "1" ]
do
	echo "$(date +%Y%m%d-%H%M%S) WARN Waiting for Redis-server to connect...."
	sleep 5
done

echo "$(date +%Y%m%d-%H%M%S) INFO Redis-server Connection Ready"
if [ -z $REDIS_MAXMEMORY ] || [ "$REDIS_MAXMEMORY" == 0 ];
then
	echo "$(date +%Y%m%d-%H%M%S) INFO Redis-server Max memory set to default..."
else
	redis-cli <<EOF
	CONFIG SET maxmemory $REDIS_MAXMEMORY
EOF
	echo "$(date +%Y%m%d-%H%M%S) INFO Redis-server Max memory set to $REDIS_MAXMEMORY ..."
fi

if [ $AUTH == "True" ];then
	redis-cli <<EOF
CONFIG SET dir /appz/data/
CONFIG SET requirepass $REDIS_DEFAULT_PASSWD
EOF
else
	echo "$(date +%Y%m%d-%H%M%S) INFO Redis Auth Disabled"
fi

if [ -z $REDIS_DEFAULT_PASSWD ] && [ $AUTH == "False" ];
then
	OPTIONS=''
else
	OPTIONS="-a $REDIS_DEFAULT_PASSWD "
fi

if [ ! -z $REDIS_USER_PASSWD ] && [ ! -z $REDIS_USER_NAME ] && [ $AUTH == "True" ];
then
	redis-cli $OPTIONS <<EOF
ACL SETUSER $REDIS_USER_NAME on allkeys +@all ~* >$REDIS_USER_PASSWD
EOF
	echo "$(date +%Y%m%d-%H%M%S) INFO Useraname and Password SET"
else
	echo "$(date +%Y%m%d-%H%M%S) INFO Username/password missing OR AUTH disabled,skipping username creation..."
fi
