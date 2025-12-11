#/bin/bash 

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
RSYNC_SECRET="${RSYNC_SECRET:-9@AZv2%5D29S740k}"
echo $RSYNC_SECRET > /etc/rsyncd.local
echo "filesync:$RSYNC_SECRET" > /etc/rsyncd.secrets
chmod 600 /etc/rsyncd.*
sed -i 's@ATTACHMENTS_STORAGE_PATH@'"${ATTACHMENTS_STORAGE_PATH}"'@g' /etc/rsyncd.conf

exec /usr/bin/rsync --no-detach --daemon --config="/etc/rsyncd.conf"
