#!/bin/bash
var=$1
LOGDATE=`date "+%Y-%m-%d %H:%M:%S,%3N"`
LF_DIR=/appz/log
LF=$LF_DIR/get_approle.log
policy="/appz/scripts/app_policy.hcl"
n_policy="/appz/cache/app_policy.hcl"
mkdir -p $LF_DIR
chmod 777 $LF_DIR
touch $LF
chmod 664 $LF
if  test $# -eq 0 ; then

      echo "get_approle.sh [arguments]"
      echo "example:- bash get_approle.sh <appname>"
      exit 0

fi
vault status &>> $LF
if [ $? -ge 1 ]
then
    echo $LOGDATE "ERROR can't access vault " |tee -a $LF
    exit 1
fi

source /appz/home/.role.conf

if [[ -z "${VAULT_ROLE_ID}" ]]; then
   echo $LOGDATE "VAULT_ROLE_ID is undefined" |tee -a $LF
   exit 1
elif [[ -z "${VAULT_SECRET_ID}" ]]; then
   echo $LOGDATE "VAULT_SECRET_ID is undefined" |tee -a $LF
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
    vault read auth/approle/role/${var}/role-id >> $LF
    if [ $? -ge 1 ]
    then
        echo $LOGDATE "INFO ${var} approle does not exist. creating it..." |tee -a $LF
    else
        echo $LOGDATE "INFO ${var} approle already exists" |tee -a $LF
    fi

	echo $LOGDATE "INFO writing policy to ${n_policy}"
	sed -e s/app-0-4/${var}/g ${policy} >> ${n_policy}
	
	cat ${n_policy}
	vault policy write ${var}_policy  ${n_policy}
	
	echo $LOGDATE "INFO creating/update approle ${var} with policy ${n_policy}"
	vault write auth/approle/role/${var}  policies=${var}_policy
	if [ $? -ge 1 ]
	then
		echo $LOGDATE "ERROR creation/update of approle ${var} failed ..." |tee -a $LF
	else
	    echo $LOGDATE "INFO creation/update approle ${var} success ..." |tee -a $LF
	fi
	
	echo $LOGDATE "INFO cleaning up policy file ${n_policy}"
	rm -rf $n_policy
else
    echo $LOGDATE "ERROR vault login failed" |tee -a $LF
fi


op=`vault read auth/approle/role/${var}/role-id |grep role_id | awk -F ' ' '{print $2}'`
df=`vault write -f auth/approle/role/${var}/secret-id |grep secret_id | awk -F ' ' '{print $2}' | head -n 1 `
echo "-----------------------------------------------"
echo VAULT_ROLE_ID=${op}
echo VAULT_SECRET_ID=${df}
echo "-----------------------------------------------"
vault token revoke -self
