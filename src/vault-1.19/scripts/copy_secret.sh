#!/bin/bash
var=$1
var2=$2
var3=$3
var4=$4
source /appz/home/.role.conf
LOGDATE=`date "+%Y-%m-%d %H:%M:%S,%3N"`
LF_DIR=/appz/log
LF=$LF_DIR/copy_secret.log
mkdir -p $LF_DIR
chmod 777 $LF_DIR
touch $LF
chmod 664 $LF
if  test $# -ne 4 ; then

      echo $LOGDATE "ERROR no param found " |tee -a $LF
      echo "copy_secret.sh [arguments]"
      echo "example:- copy_secret.sh <src_appname> <dest_appname> <src_secret_key> <dest_secret_key> "
      exit 0

fi
vault status &>> $LF
if [ $? -ge 1 ]
then
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
     echo $LOGDATE "ERROR invalid secret id or role id"  |tee -a $LF
     exit 1
else
   test=`vault login $vtoken |grep -ic appz`
fi

if [ $test -ge 1 ]
then
    vault read auth/approle/role/${var2} > /dev/null 2>&1
    if [ $? -ge 1 ]
    then
       bash /appz/scripts/get_approle.sh ${var2} |tee -a $LF
    else
       echo "$LOGDATE INFO ${var2} app-role found from vault" |tee -a $LF
    fi
    test=`vault login $vtoken |grep -ic appz`
    vault read secret/$var/$var3 > /dev/null 2>&1
    if [ $? -ge 1 ]
    then
         echo "$LOGDATE ERROR secret for $var3 not found from $var src_app_role" |tee -a $LF
         exit 1
    else
        echo "$LOGDATE INFO copying secret from ${var} to ${var2} with secret_key ${var3}" |tee -a $LF
        value=`vault read -field=value secret/$var/$var3`
        bash /appz/scripts/set_secret.sh $var2 $var4 secret=$value |tee -a $LF
        if [ $? -ge 1 ]
        then
           echo $LOGDATE "ERROR copying secret from ${var} to ${var2} with secret_key ${var4} failed" |tee -a $LF
        else
           echo $LOGDATE "INFO copying secret from ${var} to ${var2} with secret_key ${var3} done successfully" |tee -a $LF
        fi
    fi
else
    echo $LOGDATE "ERROR appz approle not successfully login" |tee -a $LF

fi
