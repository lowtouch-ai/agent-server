#!/bin/bash
var=$1
var2=$2
var3=$3
source /appz/home/.role.conf
LOGDATE=`date "+%Y-%m-%d %H:%M:%S,%3N"`
LF_DIR=/appz/log
LF=$LF_DIR/set_secret.log
mkdir -p $LF_DIR
chmod 777 $LF_DIR
touch $LF
chmod 664 $LF
if  test $# -eq 0 ; then

      echo $LOGDATE "ERROR no param found " |tee -a $LF
      echo "set_secret.sh [arguments]"
      echo "example:- bash set_secret.sh <appname>"
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

if [[ -z $var2 || -z $var3 ]]; then
   if [ $test -ge 1 ]
   then
     vault login $vtoken &>> $LF
     echo $LOGDATE "INFO vault login successfully with approle appz" >> $LF
     read -p "Enter Key: "  key
     read -p "Enter Value: " -s value
     echo
     read -p "Re-enter Value: " -s value2
     echo
     while [ $value != $value2 ]; do
             echo "Values didnt match!"
             i=0
             while  [ $i -lt 3 ];
             do
                     read -p "Enter Value: " -s value
                     echo
                     read -p "Re-enter Value: " -s value2
                     echo ""
                     ((i++))
                     if [[ $i -eq 2 ]]; then
                             echo "Retries exceeded, Exiting"
                             exit 1
                     fi
             done
     done
     vault write secret/$var/$key  value="$value" |tee -a $LF
     vl=`vault read secret/$var/$key  |grep value |awk -F ' ' '{print $2}'`
     n="n/a"
     if [ $vl == $n ]
     then
         ph=$vl
     else
         ph="${vl//?/*}"
     fi
     if [ $? -ge 1 ]
     then
         echo $LOGDATE "INFO key_value $key=$ph  write failed" |tee -a $LF
     else
         echo $LOGDATE "INFO key_value $key=$ph write succussfuly" >> $LF
     fi

   else
     echo $LOGDATE "ERROR appz approle not successfully login" |tee -a $LF
   fi
else
   if [ $test -ge 1 ]
   then
     vault login $vtoken &>> $LF
     echo $LOGDATE "INFO vault login successfully with approle appz" >> $LF
     secret_key=`echo $var3 |awk -F '=' '{print $1}'`
     if [ $secret_key == 'secret' ]
     then
        value=`echo $var3 |cut -d "=" -f 2-`
        vault write secret/$var/$var2  value=$value |tee -a $LF
        vl=`vault read secret/$var/$var2  |grep value |awk -F ' ' '{print $2}'`
        n="n/a"
        if [ $vl == $n ]
        then
           ph=$vl
        else
           ph="${vl//?/*}"
        fi
        if [ $? -ge 1 ]
        then
           echo $LOGDATE "INFO key_value $key=$ph  write failed" |tee -a $LF
        else
           echo $LOGDATE "INFO key_value $key=$ph write succussfuly" >> $LF
        fi
     else
        echo $LOGDATE "ERROR 3rd argument not starting with secret" |tee -a $LF
     fi
   else
     echo $LOGDATE "ERROR appz approle not successfully login" |tee -a $LF
   fi

fi
vault token revoke -self


