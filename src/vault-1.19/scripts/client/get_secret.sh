#!/bin/sh
set -e
LOGDATE="`date +%Y_%b_%d_%H:%M:%S`"
if [[ -z "${VAULT_APPROLE}" ]]; then
   echo $LOGDATE "ERROR Some default value because VAULT_APPROLE is undefined" 
   exit 1
fi
if [[ -z "${VAULT_ADDR}" ]]; then
   echo $LOGDATE "ERROR Some default value because VAULT_ADDR is undefined" 
   exit 1
fi
curl -k $VAULT_ADDR/v1/sys/health 
if [ $? -ge 1 ]
then
    echo $LOGDATE "ERROR can't access vault " 
    exit 1
fi
if [[ -z "${VAULT_ROLE_ID}" ]]; then
   echo $LOGDATE "ERROR Some default value because VAULT_ROLE_ID is undefined" 
   exit 1
fi
if [[ -z "${VAULT_SECRET_ID}" ]]; then
   echo $LOGDATE "ERROR Some default value because VAULT_SECRET_ID is undefined" 
   exit 1
fi
vtoken=`curl -k --request POST   --data '{"role_id": "'"$VAULT_ROLE_ID"'" , "secret_id": "'"$VAULT_SECRET_ID"'"}' $VAULT_ADDR/v1/auth/approle/login | jq -r '.auth.client_token'`
if [ $vtoken == "null" ]
then
     echo $LOGDATE "ERROR invalid secret id or role id"  
     exit 1
fi
declare -A MYMAP
key_values=`env |awk -v FS="VAULT:" 'NF>1{print $1$2}'`
if [[ -z "${key_values[@]}" ]]; then
     echo $LOGDATE "ERROR password prefix not found in env"  
else
    for key_value in $key_values; do
        n="$(cut -d'=' -f1 <<<"$key_value")"
        v="$(cut -d'=' -f2 <<<"$key_value")"
        MYMAP[${n}]=${v}
    done
    for K in "${!MYMAP[@]}"; do
        check=`curl -k  -H "X-Vault-Token: $vtoken"  -X GET  $VAULT_ADDR/v1/secret/$VAULT_APPROLE/${MYMAP[$K]} |jq -r '.errors'`
        if [ "$check" == "null" ]
        then
            mp=`curl -k  -H "X-Vault-Token: $vtoken"  -X GET  $VAULT_ADDR/v1/secret/$VAULT_APPROLE/${MYMAP[$K]} |jq -r '.data.value'`
            if [[ $mp == 'null' ]]
            then
                dir="/appz/home/.ssh/"
                if ! [ -d $dir ]; then
                    echo $LOGDATE "INFO creating $dir folder"  
                    mkdir -p $dir
                    if [ $? -ge 1 ]
                    then
                        echo $LOGDATE "ERROR $dir folder not created " 
                        exit 1
                    else
                        echo $LOGDATE "INFO $dir folder created " 
                    fi
                else
                   echo $LOGDATE "INFO $dir folder already exists"  
                fi
                file="$dir$K.pem"
                curl -k  -H "X-Vault-Token: $vtoken"  -X GET  $VAULT_ADDR/v1/secret/$VAULT_APPROLE/${MYMAP[$K]} |jq -r '.data.cert' > $file
                if  [ -f $file ]; then
                   chmod 600 $file
                   echo $LOGDATE "INFO $file permission changed " 
                else
                   echo $LOGDATE "INFO $file not found " 
                fi
                if [ -s $file ]
                then
                    echo $LOGDATE "INFO copied ${MYMAP[$K]} to $file"  
                else
                    echo $LOGDATE "ERROR copy ${MYMAP[$K]} to $file failed"  
                fi
                    export $K="$file"
                    array+=("-D"$K"="$file)
            else
                export $K="$mp"
                array+=("-D"$K"="$mp)
                fluentd+=("$mp")
                fluentd+=("-p$mp")
                fluentd+=("-D"$K"="$mp)
            fi
            if [[ -z "${MYMAP[$K]}" ]]; then
                 echo $LOGDATE "Failed to retrieve ${MYMAP[$K]}"
            else
                 ct=`echo -n $mp |wc -c`
                 count=`expr $ct - 1`
                 df=`echo $mp |awk 'BEGIN{FS=OFS=""} {for(i=2;i<='$count';i++) $i="*"}1'`
                 echo $LOGDATE "INFO ${MYMAP[$K]} found: $df" 
            fi
        else
            VAULT_GET_ADDR=$(echo $VAULT_ADDR|awk -F ':' '{print $1":"$2}' |sed 's/https/http/g')
            code=`curl $VAULT_GET_ADDR/vault/generate_password | head -n1 | awk '{print $1;}'`
            if [[ $code != '404' ]]
            then
                 echo $LOGDATE "Generating Password form vault " 
                 if [[ -z "$VAULT_APPROLE" ]];then
                    echo $LOGDATE "ERROR VAULT_APPROLE env not found " 
                    exit 1
                 fi
                 if [[ -z "${MYMAP[$K]}" ]];then
                    echo $LOGDATE "ERROR KEY env not found " 
                    exit 1
                 fi
                 curl -d "$VAULT_APPROLE:${MYMAP[$K]}" -X POST $VAULT_GET_ADDR/vault/generate_password
                 mp=`curl -k  -H "X-Vault-Token: $vtoken"  -X GET  $VAULT_ADDR/v1/secret/$VAULT_APPROLE/${MYMAP[$K]} |jq -r '.data.value'`
                 if [[ "$mp" == "null" ]];then
                     echo $LOGDATE "INFO ${MYMAP[$K]} found as null from vault" 
                     exit 1
                 fi
                 if [[ -z "$mp" ]];then
                     echo $LOGDATE "INFO ${MYMAP[$K]} not found from vault" 
                     exit 1
                 fi
                 if [[ -z "$K" ]];then
                     echo $LOGDATE "INFO ${MYMAP[$K]} not found from vault" 
                     exit 1
                 fi
                 export $K="$mp"
                 array+=("-D"$K"="$mp)
                 fluentd+=("$mp")
                 fluentd+=("-p$mp")
                 fluentd+=("-D"$K"="$mp)
                 ct=`echo -n $mp |wc -c`
                 count=`expr $ct - 1`
                 df=`echo $mp |awk 'BEGIN{FS=OFS=""} {for(i=2;i<='$count';i++) $i="*"}1'`
                 echo $LOGDATE "INFO ${MYMAP[$K]} found: $df" 
            else
               echo $LOGDATE "INFO ${MYMAP[$K]} not found from vault" 
            fi
        fi
    done
export APPZ_JAVA_SECRETS="${array[@]}"
env_fluentd=`echo ${fluentd[@]}|sed -e 's/\s\+/|/g'`
if [[ -z "${env_fluentd}" ]]
then
    echo "no secrets found from vault"
else
    export APPZ_FLUENTD_SECRETS="$env_fluentd"
fi
fi
