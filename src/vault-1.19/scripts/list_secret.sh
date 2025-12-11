#!/bin/bash
var=$1
source /appz/home/.role.conf
LOGDATE=`date "+%Y-%m-%d %H:%M:%S,%3N"`
out="/appz/cache/vault_list"
> $out
LF_DIR=/appz/log
LF=$LF_DIR/list_secret.log
mkdir -p $LF_DIR
chmod 777 $LF_DIR
touch $LF
chmod 664 $LF
if  test $# -eq 0 ; then

      echo $LOGDATE "ERROR no param found " |tee -a $LF
      echo "list_secret.sh [arguments]"
      echo "example:- bash list_secret.sh <appname>"
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
    vault login $vtoken &>> $LF
    echo $LOGDATE "INFO vault login successfully with approle appz" >> $LF
    echo $LOGDATE "INFO listing vault secret from appz" >> $LF
    vault list  secret/$var | grep -v -e Keys -e - >> $out
    echo ""
    echo "CONTENTS OF THE VAULT OF $var"
    echo "--------------------------------------------------------"
    while read p; do
      value=`vault read secret/$var/$p |grep value |awk -F ' ' '{print $1}'`	    
      if [[ $value == 'value' ]]
      then 	      
        gh=`vault read -field=value secret/$var/$p `
        ct=`echo -n $gh |wc -c`
        count=`expr $ct - 1`
        df=`echo $gh |awk 'BEGIN{FS=OFS=""} {for(i=2;i<='$count';i++) $i="*"}1'` 
        echo $p = $df
      else
	lc=`vault read -field=cert secret/$var/$p|wc -l`
        if [[ $lc != '1' ]]	
        then		
            cert=`vault read -field=cert secret/$var/$p|sed -n '1p;1n;2p;2s/./*/gp;$!N;$!D;p'` 
            m="$p =\n${cert}"
            echo -e "$m"
        else
	    cert=`vault read -field=cert secret/$var/$p|fold -s -w40|sed -n '1p;1n;2p;2s/./*/gp;$!N;$!D;p'`
            m="$p =\n${cert}"
            echo -e "$m"    	    
        fi    
      fi	
    done <$out
    echo "--------------------------------------------------------"
    echo ""
    vault token revoke -self
    if [ $? -ge 1 ]
    then
         echo $LOGDATE "ERROR listing vault secret from appz failed"  |tee -a $LF
    else
         echo $LOGDATE "INFO  vault secret from appz listed success"  >>  $LF
    fi

else
    echo $LOGDATE "ERROR appz approle not successfully login" |tee -a $LF
fi
rm $out
