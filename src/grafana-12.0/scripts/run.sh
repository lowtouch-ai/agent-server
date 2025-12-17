#!/bin/bash -e
VAULT_GET_ADDR=$(echo $VAULT_ADDR|awk -F ':' '{print $1":"$2}' |sed 's/https/http/g')
source <(curl -s $VAULT_GET_ADDR/get_secret.sh)

export GF_SECURITY_ADMIN_PASSWORD=$ADMIN_PASSWORD


PERMISSIONS_OK=0

if [ ! -r "$GF_PATHS_CONFIG" ]; then
    echo "GF_PATHS_CONFIG='$GF_PATHS_CONFIG' is not readable."
    PERMISSIONS_OK=1
fi

if [ ! -w "$GF_PATHS_DATA" ]; then
    echo "GF_PATHS_DATA='$GF_PATHS_DATA' is not writable."
    PERMISSIONS_OK=1
fi

if [ ! -r "$GF_PATHS_HOME" ]; then
    echo "GF_PATHS_HOME='$GF_PATHS_HOME' is not readable."
    PERMISSIONS_OK=1
fi

if [ $PERMISSIONS_OK -eq 1 ]; then
    echo "You may have issues with file permissions, more information here: http://docs.grafana.org/installation/docker/#migration-from-a-previous-version-of-the-docker-container-to-5-1-or-later"
fi

if [ ! -d "$GF_PATHS_PLUGINS" ]; then
    mkdir "$GF_PATHS_PLUGINS"
fi


for VAR_NAME in $(env | grep '^GF_[^=]\+__FILE=.\+' | sed -r "s/([^=]*)__FILE=.*/\1/g"); do
    VAR_NAME_FILE="$VAR_NAME"__FILE
    if [ "${!VAR_NAME}" ]; then
        echo >&2 "ERROR: Both $VAR_NAME and $VAR_NAME_FILE are set (but are exclusive)"
        exit 1
    fi
    echo "Getting secret $VAR_NAME from ${!VAR_NAME_FILE}"
    export "$VAR_NAME"="$(< "${!VAR_NAME_FILE}")"
    unset "$VAR_NAME_FILE"
done

modify_dashboard_titles() {
    local dashboard_path=$1
    local temp_path="/tmp/modified_$(basename "$dashboard_path")"

    jq '.title = (.title | sub("(?i)^AppZ"; ""))' "$dashboard_path" > "$temp_path" && mv "$temp_path" "$dashboard_path"
}
declare -a dashboards=("AppZGraylogV1.json" "AppZBlackBoxV3.json" "AppZNodesv5.json" "AppZPodsV1.json" "AppZOpenSearchV1.json" "AppZDockerV3.json")

if [ "${GL_DASHBOARD:-0}" -eq 1 ]; then
    echo "Copying selected dashboards only..."
    for dashboard in "${dashboards[@]}"; do
        modify_dashboard_titles "/tmp/dashboards/$dashboard"
        cp "/tmp/dashboards/$dashboard" /var/lib/grafana/dashboards/
    done
else
    echo "Copying all dashboards..."
    cp /tmp/dashboards/* /var/lib/grafana/dashboards/
fi

if [ -f "/etc/grafana/grafana.ini" ]; then
    echo "Updating Grafana OAuth settings in grafana.ini..."

    sed -i '/^\[auth\.generic_oauth\]/,/^\[/{s|^;enabled =.*|enabled = true|}' /etc/grafana/grafana.ini
    sed -i "s|^;root_url =.*|root_url = ${ROOT_URL}|" /etc/grafana/grafana.ini
    sed -i "s|^;token_url =.*|token_url = ${KEYCLOCK_INTERNAL_URL}/auth/realms/lowtouch.ai/protocol/openid-connect/token|" /etc/grafana/grafana.ini
    sed -i "s|^;auth_url =.*|auth_url = ${KEYCLOCK_EXTERNAL_URL}/auth/realms/lowtouch.ai/protocol/openid-connect/auth|" /etc/grafana/grafana.ini
    sed -i "s|^;api_url =.*|api_url = ${KEYCLOCK_EXTERNAL_URL}/auth/realms/lowtouch.ai/protocol/openid-connect/userinfo|" /etc/grafana/grafana.ini

    sed -i "s|^;allow_sign_up =.*|allow_sign_up = true|" /etc/grafana/grafana.ini
    sed -i "s|^;scopes =.*|scopes = openid profile email|" /etc/grafana/grafana.ini

    sed -i "s|^;name =.*|name = ${OAUTH_NAME}|" /etc/grafana/grafana.ini
    sed -i "s|^;client_id =.*|client_id = ${OAUTH_CLIENT_ID}|" /etc/grafana/grafana.ini
    sed -i "s|^;client_secret =.*|client_secret = ${OAUTH_CLIENT_SECRET}|" /etc/grafana/grafana.ini

    echo "Grafana OAuth settings updated successfully."
else
    echo "WARNING: grafana.ini not found! Skipping OAuth settings update."
fi

export HOME="$GF_PATHS_HOME"

if [ ! -z "${GF_INSTALL_PLUGINS}" ]; then
  OLDIFS=$IFS
  IFS=','
  for plugin in ${GF_INSTALL_PLUGINS}; do
    IFS=$OLDIFS
    grafana-cli --pluginsDir "${GF_PATHS_PLUGINS}" plugins install ${plugin}
  done
fi

echo "Adding data source in grafana"
sed -i  's|sample_url|'"$PROM_URL"'|' /etc/grafana/provisioning/datasources/datasource.yaml

rm /usr/share/grafana/public/dashboards/home.json 
cp /var/lib/grafana/dashboards/AppZNodesv5.json  /usr/share/grafana/public/dashboards/home.json

exec grafana-server                                         \
  --homepath="$GF_PATHS_HOME"                               \
  --config="$GF_PATHS_CONFIG"                               \
  "$@"                                                      \
  cfg:default.log.mode="console"                            \
  cfg:default.paths.data="$GF_PATHS_DATA"                   \
  cfg:default.paths.logs="$GF_PATHS_LOGS"                   \
  cfg:default.paths.plugins="$GF_PATHS_PLUGINS"             \
  cfg:default.paths.provisioning="$GF_PATHS_PROVISIONING"
