#!/bin/bash

VAULT_GET_ADDR=$(echo $VAULT_ADDR|awk -F ':' '{print $1":"$2}' |sed 's/https/http/g')
source <(curl -s $VAULT_GET_ADDR/get_secret.sh)

mdpass=$(printf '%s' "$PGPASSWORD" | md5sum | awk '{print $1}')

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
if [[ ! -z $STATEMENT_TIME ]] ; then

    echo "INFO statement time found from env $STATEMENT_TIME"
    current_value=`awk '/statement_timeout/ {print$3}' $POSTGRESQL_DATA/postgresql.conf`
    if [ "$current_value" == 0 ] ; then
         check_hash=`awk '/statement_timeout/ {print$1}' $POSTGRESQL_DATA/postgresql.conf`
	 if [ "$check_hash" == "#statement_timeout" ] ; then
               sed -i '/statement_timeout/ s/#statement_timeout = 0/statement_timeout = '"$STATEMENT_TIME"'/g' $POSTGRESQL_DATA/postgresql.conf
               if [ "$?" -eq 0 ]; then
                    echo "INFO successfully updated the statement time "
               else
                    echo "ERROR failed to update the statement time"
               fi
	 else
	       sed -i '/statement_timeout/ s/statement_timeout = 0/statement_timeout = '"$STATEMENT_TIME"'/g' $POSTGRESQL_DATA/postgresql.conf
               if [ "$?" -eq 0 ]; then
                    echo "INFO successfully updated the statement time "
               else
                    echo "ERROR failed to update the statement time"
	       fi	    
	 fi      
    else
         check_hash=`awk '/statement_timeout/ {print$1}' $POSTGRESQL_DATA/postgresql.conf`
	 if [ "$check_hash" == "#statement_timeout" ] ; then
             sed -i '/statement_timeout/ s/#statement_timeout = '"$current_value"'/statement_timeout = '"$STATEMENT_TIME"'/g' $POSTGRESQL_DATA/postgresql.conf
             if [ "$?" -eq 0 ]; then
                  echo "INFO successfully updated the statement time "
             else
                  echo "ERROR failed to update the statement time"
             fi
	 else
	       sed -i '/statement_timeout/ s/statement_timeout = '"$current_value"'/statement_timeout = '"$STATEMENT_TIME"'/g' $POSTGRESQL_DATA/postgresql.conf
             if [ "$?" -eq 0 ]; then
                    echo "INFO successfully updated the statement time "
             else
                    echo "ERROR failed to update the statement time"
	       fi	    
	 fi
    fi
fi
echo "Starting Postgress Master Setup"
set +e
chown postgres. "$POSTGRESQL_DATA" -R
chmod 700 -R "$POSTGRESQL_DATA"
grep -i "0.0.0.0" "$POSTGRESQL_DATA/pg_hba.conf"  1> /dev/null 
if [ "$?" -eq 0 ]
then
        echo "conf  file already changed"
else
        echo "host replication $POSTGRESQL_REP_USER  0.0.0.0/0 md5" >> "$POSTGRESQL_DATA/pg_hba.conf"
	
fi

su - postgres -c "psql -c '\du ' "  |grep $POSTGRESQL_REP_USER 1> /dev/null

if [ "$?" -eq 0 ]
then
         su - postgres -c "psql <<-EOSQL
	 DROP USER $POSTGRESQL_REP_USER;
	 DROP DATABASE $POSTGRESQL_REP_USER;
EOSQL"

fi	
su - postgres -c  "psql  <<-EOSQL
         CREATE USER "$POSTGRESQL_REP_USER" WITH REPLICATION ENCRYPTED PASSWORD '"$mdpass"';
         CREATE DATABASE "$POSTGRESQL_REP_USER";
EOSQL"
su - postgres -c "psql -c '\du ' "  |grep $POSTGRESQL_REP_USER 1> /dev/null 
if [ "$?" -eq 0 ]     	
then 	
   echo "Created or updated REPLICATION successfully"
else 
   echo "Failed REPLICATION user creation"
   exit 1   
fi
su - postgres -c  "psql  <<-EOSQL
         ALTER SYSTEM SET listen_addresses TO '*';
         SELECT pg_reload_conf();

EOSQL"

if [ "$?" -eq 0 ]
then 
   echo " Postgress Master Setup completed " 
else
   echo " Postgress Master Setup failed " 
fi
