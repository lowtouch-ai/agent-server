#!/bin/bash
LOGDATE="`date +%Y_%b_%d_%H:%M:%S`"
if [ "$ENABLE_HA" == "yes" ]; then
     echo "enabling HA mode"
     export MYSQL_HOST=127.0.0.1:3306
fi

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
   echo "waiting for $VAULT_ADDR..."
   sleep 1
   c=`expr $c + 1`
   if [ $c -gt $mc ];then
      echo "FATAL: vault timeout... exiting"
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
if [ -z $SITE_PRIVATE_KEY ] && [ -z $SITE_CERT ]; then
   echo "vault envs for cert not found, proceeding with default certs"	
else	
   if [ -f $SITE_PRIVATE_KEY ] && [ -f $SITE_CERT ]; then
      openssl x509 -in $SITE_CERT  -inform PEM -noout &> /dev/null
      if [ $? -eq  0 ]; then
         openssl rsa -in $SITE_PRIVATE_KEY  -check -noout &> /dev/null
         if [ $? -eq  0 ]; then
            cp $SITE_PRIVATE_KEY $CERT_KEY_PATH
            if [ $? -eq  0 ]; then
               echo "copy $SITE_PRIVATE_KEY to $CERT_KEY_PATH successfully"
            else
               echo "failed to copy $SITE_PRIVATE_KEY to $CERT_KEY_PATH successfully"
            fi
            cp $SITE_CERT $CERT_PATH
            if [ $? -eq  0 ]; then
               echo "copy $SITE_CERT to $CERT_PATH successfully"
            else
               echo "failed to copy $SITE_CERT to $CERT_PATH successfully"
            fi
         else
            echo "fail to valid $SITE_PRIVATE_KEY, proceeding with default certs"
         fi
      else
         echo "fail to valid $SITE_CERT, proceeding with default certs"
      fi
   else
      echo "Certs are not present in vault, proceeding with default certs" 	 
   fi
fi   
count=1
maxcount=90
HOST=$(echo "$MYSQL_HOST" | awk -F':' '{print $1}')
while ! mysql -h "$HOST" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" -e "show databases;" | grep -ic Database > /dev/null 2>&1; do
    echo "We are waiting for mariadb to come up."
    sleep 1
    count=`expr $count + 1`
    if [ $count -gt $maxcount ]; then
        >&2 echo "We have been waiting for start Mariadb too long already; failing."
        exit 1
    fi;
done 
echo "mariadb connected"
exec /usr/local/bin/docker-entrypoint.sh  apache2-foreground

