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

env >> /appz/scripts/.env
if [ "$ENABLE_HA" == "yes" ]; then
     echo "enabling HA mode"
     export MYSQL_HOST=127.0.0.1:3306

else     
     supervisorctl stop haproxy
     if [ $? -eq  0 ]; then
        echo "haproxy service stoped"
     else
        echo "failed to stop haproxy service"
     fi	
     supervisorctl stop rsync
     if [ $? -eq  0 ]; then
        echo "rsync service stoped"
     else
        echo "failed to stop rsync service"
     fi
     supervisorctl stop lsyncd
     if [ $? -eq  0 ]; then
	echo "lsyncd service stoped"
     else
        "failed to stop lsyncd service"
     fi	
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
maxcounter=90

counter=1
while ! supervisorctl  status httpd | grep -ic RUNNING > /dev/null 2>&1; do
    sleep 1
    counter=`expr $counter + 1`
    if [ $counter -gt $maxcounter ]; then
        >&2 echo "We have been waiting for start HTTPD too long already; failing."
        exit 1
    fi;
done

count=1
maxcount=30
d=$(wget --tries=2 --server-response "http://localhost:80" 2>&1 | awk '/^  HTTP/{print $2}'|head -1)
while [ "$d" != "301" ] &&  [ "$d" != "200" ] && [ "$d" != "302" ];do
   echo "wordpress copy yet to complete"
   sleep 1
   count=`expr $count + 1`
    if [ $count -gt $maxcount ]; then
        >&2 echo "We have been waiting to start HTTPD too long already; failing."
        exit 1
    fi
   d=$(wget --tries=2 --server-response http://localhost:80 2>&1 | awk '/^  HTTP/{print $2}'|head -1)
   echo $d
done

mkdir -p /var/www/html/wp-content/uploads 
dir=/appz/home/.wp-cli
if [[ ! -e $dir ]]; then
    mkdir $dir
elif [[ ! -d $dir ]]; then
    echo "$dir already exists but is not a directory" 1>&2
fi
echo "path: $WP_INSTALL_DIR" >/appz/home/.wp-cli/config.yml
#Wait for mariadb available
if [[ $MYSQL_HOST == "127.0.0.1:3306" ]] ; then
     echo "MYSQL_HOST is available,checking for the haprxoy service"
     mysql -h 127.0.0.1 -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" -e "show databases;" > /dev/null 2>&1;
else
     echo "Installing the wordpress"
fi
if [[ -z "${SITE_URL}" ]]; then
   echo SITE_URL not found from ENV creating it ... 	
   SITE_URL="https://"$APPZ_INSTANCE_PREFIX"-"${APPZ_APP_NAME:-wordpress}"."${APPZ_BASE_DOMAIN:-appzdemo.com}
fi
wp --allow-root core install --url=$SITE_URL --title="$SITE_TITLE" --admin_user=$ADMIN_USER --admin_password=$ADMIN_PASSWORD --admin_email=$ADMIN_EMAIL 
if [[ ! -z "${ADMIN_PASSWORD_HASH}" ]]; then
	wp --allow-root db query "UPDATE wp_users SET user_pass='$ADMIN_PASSWORD_HASH' WHERE ID = 1;"
fi
wp --allow-root maintenance-mode activate
wp --allow-root option update blogdescription "$SITE_DESCRIPTION"
wp --allow-root option update home "$SITE_URL"
wp --allow-root option update siteurl "$SITE_URL"
wp --allow-root option update  comment_moderation "1"
wp --allow-root option update comment_registration "1"
wp --allow-root option update users_can_register "0"
wp --allow-root option update default_comment_status "close"
[ ! -z "$SITE_TITLE" ] && wp --allow-root option update blogname "$SITE_TITLE"
cd /root
python3  /appz/scripts/activate.py
python3  /appz/scripts/options_import.py
chown -R www-data:www-data /var/www/html/
#__INIT_PLACEHOLDER__
wp --allow-root maintenance-mode deactivate
echo "wp-init completed successfully!"
echo "WP-INIT:SUCCESS!"
set +e
