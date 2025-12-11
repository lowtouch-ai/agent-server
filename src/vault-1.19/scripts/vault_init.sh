#!/bin/bash
LOGDATE=`date "+%Y-%m-%d %H:%M:%S,%3N"`
echo $LOGDATE "INFO vault init..."
sleep 10
data=/appz/cache/.data
> $data
vault_key=/appz/home/.vault_keys
vault operator init >> $data 2>&1
value=$( grep -ic  "unseal" $data )
if [ $value -ge 1 ]
then
   > $vault_key
   chmod 400 $vault_key
   cat $data  |grep Unseal | awk -F " " '{print $1"_"$3"="$4}'| awk -F ':' '{print $1$2}' >> $vault_key
   cat $data | grep Root |  awk -F " " '{print $1"_"$3"="$4}'| awk -F ':' '{print $1$2}' >> $vault_key
   source $vault_key
   echo $LOGDATE "INFO vault unsealing ..."
   vault operator unseal $Unseal_1
   vault operator unseal $Unseal_2
   vault operator unseal $Unseal_3
   echo $LOGDATE "INFO vault login with root ..."
   vault login $Initial_Token 1>&2
   echo $LOGDATE "INFO creating approle for appz ..."
   vault auth enable approle
   vault policy write appz_policy  /appz/scripts/appz_policy.hcl
   vault write auth/approle/role/appz  policies="appz_policy"
   vault secrets enable -path=secret kv
   vault write sys/auth/approle/tune default_lease_ttl=60
   vault write sys/auth/approle/tune max_lease_ttl=180
   if [ $? -ge 1 ]
   then
        echo $LOGDATE "INFO create approle for appz failed ..."
   else
        echo $LOGDATE "INFO create approle for appz successfully ..."
   fi
   rm -rf $data
else
   echo $LOGDATE "INFO vault already init"
   value2=$(vault status |  grep -ic "Progress")
   source $vault_key
   if [ $value2 -ge 1 ]
   then
        vault operator unseal $Unseal_1
        vault operator unseal $Unseal_2
        vault operator unseal $Unseal_3
   fi
   vault login $Initial_Token 1>&2
   vault read auth/approle/role/appz/role-id
   if [ $? -ge 1 ]
   then
       vault policy write appz_policy  /appz/scripts/appz_policy.hcl
       vault write auth/approle/role/appz  policies="appz_policy"
       vault write sys/auth/approle/tune default_lease_ttl=60
       vault write sys/auth/approle/tune max_lease_ttl=180
   fi
fi
op=`vault read auth/approle/role/appz/role-id |grep role_id | awk -F ' ' '{print $2}'`
df=`vault write -f auth/approle/role/appz/secret-id |grep secret_id | awk -F ' ' '{print $2}' | head -n 1 `
echo "export VAULT_ROLE_ID=$op" > /appz/home/.role.conf
echo "export VAULT_SECRET_ID=$df" >> /appz/home/.role.conf
chmod 400 /appz/home/.role.conf
source /appz/home/.role.conf
if [[ -z "${VAULT_ROLE_ID}" ]]; then
      echo $LOGDATE "VAULT_ROLE_ID is undefined" |tee -a $LF
      exit 1
fi
if [[ -z "${VAULT_SECRET_ID}" ]]; then
       echo $LOGDATE "VAULT_SECRET_ID is undefined" |tee -a $LF
       exit 1
fi
vtoken=`vault write -field=token auth/approle/login role_id=$VAULT_ROLE_ID secret_id=$VAULT_SECRET_ID`
if [ $? -ge 1 ]
then
     echo $LOGDATE "Failed to get login!!! Invalid VAULT_ROLE_ID and/or VAULT_SECRET_ID"  |tee -a $LF
     exit 1
else
     result=`vault login $vtoken |grep -ic appz`
     echo "Token test result: "$result
fi
vault login $vtoken
vault token revoke -self
