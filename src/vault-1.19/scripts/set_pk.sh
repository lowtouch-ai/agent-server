#!/bin/bash
var=$1
var2=$2
var3=$3
source /appz/home/.role.conf
LOGDATE=`date "+%Y-%m-%d %H:%M:%S,%3N"`
LF_DIR=/appz/log
LF=$LF_DIR/set_pk.log
mkdir -p $LF_DIR
chmod 777 $LF_DIR
touch $LF
chmod 664 $LF
if  test $# -eq 0 ; then

      echo $LOGDATE "ERROR no param found " |tee -a $LF
      echo "/appz/scripts/set_pk.sh <app-name> <key> pk=<path-to-pf-file>"
      echo "example:- /appz/scripts/set_pk.sh sitesee-2-0 client-vm-pk pk=/appz/cache/pk01.pem"
      exit 0

fi
if [[ -z $var2 || -z $var3 || -z $var ]]; then

      echo $LOGDATE "ERROR no param found " |tee -a $LF
      echo "/appz/scripts/set_pk.sh <app-name> <key> pk=<path-to-pf-file>"
      echo "example:- /appz/scripts/set_pk.sh sitesee-2-0 client-vm-pk pk=/appz/cache/pk01.pem"
      exit 0

fi
vault status &>> $LF
if [ $? -ge 1 ]
then
    vault status	
    echo $LOGDATE "ERROR can't access vault " |tee -a $LF
    exit 1
fi


if [[ -z "${VAULT_ROLE_ID}" ]]; then
   echo $LOGDATE "ERROR Some default value because VAULT_ROLE_ID is undefined" |tee -a $LF
   exit 1
fi

if [[ -z "${VAULT_SECRET_ID}" ]]; then
   echo $LOGDATE "ERROR Some default value because VAULT_SECRET_ID is undefined" |tee -a $LF
   exit 1
fi

vtoken=`vault write -field=token auth/approle/login role_id=$VAULT_ROLE_ID secret_id=$VAULT_SECRET_ID`
if [ $? -ge 1 ]
then
     vault write -field=token auth/approle/login role_id=$VAULT_ROLE_ID secret_id=$VAULT_SECRET_ID     	
     echo $LOGDATE "ERROR invalid secret id or role id"  |tee -a $LF
     exit 1
else
   test=`vault login $vtoken |grep -ic appz`
fi

if [ $test -ge 1 ]
then
     vault login $vtoken &>> $LF
     echo $LOGDATE "INFO vault login successfully with approle appz" >> $LF
     secret_key=`echo $var3 |awk -F '=' '{print $1}'`
     if [ $secret_key == 'pk' ]
     then
        value=`echo $var3 |awk -F '=' '{print $2}'`
	dir=`dirname  $value`
	if [ $dir != '/appz/cache' ]
        then	
            echo $LOGDATE "ERROR the path should be in /appz/cache" |tee -a $LF
            exit 1
        fi    
        vault write secret/$var/$var2  cert=@$value &>> $LF
        if [ $? -ge 1 ]
        then
           vault write secret/$var/$var2  cert=@$value		
           echo $LOGDATE "INFO key_value $var2 write failed" |tee -a $LF
        else
           echo $LOGDATE "INFO key_value $var2 write succussfuly" |tee -a $LF
        fi
     rm $value  
     elif [ $secret_key == 'pkk' ]
     then 
        value=`echo $var3 |awk -F '=' '{print $2}'`
        vault write secret/$var/$var2  cert=@$value &>> $LF
        if [ $? -ge 1 ]
        then
           vault write secret/$var/$var2  cert=@$value		
           echo $LOGDATE "INFO key_value $var2 write failed" |tee -a $LF
        else
           echo $LOGDATE "INFO key_value $var2 write succussfuly" |tee -a $LF
        fi

   	     

     else
        echo $LOGDATE "ERROR 3rd argument not starting with pk or pkk" |tee -a $LF
     fi
   else
     echo $LOGDATE "ERROR appz approle not successfully login" |tee -a $LF
fi
   

vault token revoke -self

