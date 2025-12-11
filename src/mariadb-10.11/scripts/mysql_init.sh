
#!/bin/bash
maxcounter=90

counter=1
while ! netstat -tln |grep '3306' > /dev/null 2>&1; do
    echo "waiting for mysql to start listening on 3306.."	
    sleep 1
    counter=`expr $counter + 1`
    if [ $counter -gt $maxcounter ]; then
        >&2 echo "We have been waiting for start MYSQL too long already; failing."
        exit 1    
    fi;
done
YAML_FILE=/appz/scripts/mariadb-contents/setup.yaml
if [ "$?" -eq 0 ] && [ -f "$YAML_FILE" ]; then
        echo "MariaDB started successfully"
        echo "Found setup.yaml and proceeds running the script"
else
        echo "MariaDB started successfully"
        echo "No setup.yaml found for running the script, Skipping..."
	exit 1 
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
   VAULT_GET_ADDR=$(echo $VAULT_ADDR|awk -F ':' '{print $1":"$2}' |sed 's/https/http/g')
   source <(curl -s $VAULT_GET_ADDR/get_secret.sh)
fi

maxcounter=90

counter=1
if [[ -z "${MYSQL_CONNECTUSER}" ]]; then
	echo "MYSQL_CONNECTUSER is undefined, adding root as MYSQL_CONNECTUSER variable"
	export MYSQL_CONNECTUSER="root"
	if [[ -z "${MYSQL_ROOT_PASSWORD}" ]]; then
		echo "MYSQL_ROOT_PASSWORD is undefined"
		exit 1
        fi
fi

if [[ -z "${MYSQL_CONNECTIONDB}" ]]; then
        echo "MYSQL_CONNECTIONDB is undefined, adding mysql as MYSQL_CONNECTIONDB variable"
        export MYSQL_CONNECTIONDB="mysql"
fi

while ! mysql -u $MYSQL_CONNECTUSER -p$MYSQL_ROOT_PASSWORD -e "SHOW DATABASES"  | grep $MYSQL_CONNECTIONDB > /dev/null 2>&1 ; do
    sleep 3
    counter=`expr $counter + 1`
    if [ $counter -gt $maxcounter ]; then
        >&2 echo "We have been waiting for MariaDB too long already; failing."
        exit 1
    else
	echo "Waiting for MariaDB to start"
    fi;
done
python3 /appz/scripts/activate_mariadb.py
if [ "$?" -eq 0 ]; then
	echo "activate_mariadb.py script runs successfully"
else
	echo "Some issues with the script encountered"
fi
	
