#!/bin/bash
var=$APPROLE
var2=$KEY
var3=$PASS
source /appz/home/.role.conf
LOGDATE=`date "+%Y-%m-%d %H:%M:%S,%3N"`
LF_DIR=/appz/log
LF=$LF_DIR/vault-provision.log
mkdir -p $LF_DIR
chmod 777 $LF_DIR
touch $LF
chmod 664 $LF
export VAULT_ADDR=https://localhost:8200
export VAULT_SKIP_VERIFY=true
if [[ -z "$APPROLE" ]];then
        echo $LOGDATE "ERROR APPROLE env not found " |tee -a $LF
        exit 1
fi
if [[ -z "$KEY" ]];then
        echo $LOGDATE "ERROR KEY env not found " |tee -a $LF
        exit 1
fi
if [[ -z "$PASS" ]];then
        echo $LOGDATE "ERROR PASS env not found " |tee -a $LF
        exit 1
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

if [[ -z $var2 || -z $var3 ]]; then
   echo $LOGDATE "ERROR KEY SECRET params missing" |tee -a $LF
   exit 1
else
   if [ $test -ge 1 ]
   then
     vault login $vtoken &>> $LF
     echo $LOGDATE "INFO vault login successfully with approle appz" >> $LF
     vault write secret/$var/$var2  value=$var3 |tee -a $LF
     if [ $? -ge 1 ]
     then
         echo $LOGDATE "ERROR failed to write the vault" |tee -a $LF
         exit 1
     fi
     vl=`vault read secret/$var/$var2  |grep value |awk -F ' ' '{print $2}'`
     if [[ -z vl ]]; then
             echo $LOGDATE "ERROR key value not found in vault" |tee -a $LF
             exit 1
     fi
     n="n/a"
     m="null"
     if [ $vl == $n ]
     then
        ph=$vl
     else
        ph="${vl//?/*}"
     fi
     if [ $? -ge 1 ]
     then
        echo $LOGDATE "INFO key_value $key=$ph  write failed" |tee -a $LF
        exit 1
     else
        if [ $vl == $m ]
        then
             echo $LOGDATE "INFO key_value $key=$ph write failed" >> $LF
             exit 1
        else
             echo $LOGDATE "INFO key_value $key=$ph write succussfuly" >> $LF
        fi
     fi
   else
     echo $LOGDATE "ERROR appz approle not successfully login" |tee -a $LF
     exit 1
   fi

fi
if [ $? -eq  0 ]; then
   echo "revoking vault token...."	
   vault token revoke -self
fi   
