#!/bin/bash

restore_configs() {
  CONFIG_DIR="/etc/apache2/sites-enabled"
  CERT_DIR="/etc/letsencrypt/live/"
  PERSIST_DIR="/appz/data"
  
  mkdir -p "${CONFIG_DIR}"
  
  if ls "${PERSIST_DIR}"/*.conf > /dev/null 2>&1; then
    for config_file in "${PERSIST_DIR}"/*.conf; do
      filename=$(basename "$config_file")
      target_path="${CONFIG_DIR}/${filename}"
      echo "Restoring config file ${filename}"
      cp -f "${config_file}" "${target_path}"
    done
  else
    echo "No persistent configs found in ${PERSIST_DIR}"
  fi
}
if env | grep "VAULT:" > /dev/null 2>&1; then
  c=1
  mc=180
  while ! curl -k -o /dev/null -s -w "%{http_code}\n" -k "$VAULT_ADDR/v1/sys/health" | grep "200" > /dev/null 2>&1; do
    echo "waiting for $VAULT_ADDR..."
    sleep 1
    c=$(expr $c + 1)
    if [ $c -gt $mc ]; then
      echo "FATAL: vault timeout... exiting"
      exit 1
    fi
  done
  VAULT_GET_ADDR=$(echo "$VAULT_ADDR" | awk -F ':' '{print $1":"$2}' | sed 's/https/http/g')
  source <(curl -s "$VAULT_GET_ADDR/get_secret.sh")
fi

restore_configs

exec /usr/sbin/apache2 -DFOREGROUND
