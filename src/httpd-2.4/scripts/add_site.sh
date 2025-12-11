#!/bin/bash

function show_usage() {
  echo "Usage: add_site -s|--servername VALUE -t|--targeturl VALUE [-p|--protocol VALUE]"
  echo '''
  NAME
        add_site

  SYNOPSIS
        add_site [PARAMS]

  DESCRIPTION
        add_site generates httpd VirtualHost config in /appz/data/
        Certificates are managed directly in /etc/letsencrypt/ by Certbot
        Configs are copied to /etc/apache2/sites-enabled/ by startup script

  PARAMS
        -s| --servername     a dns name: ex: demo2025a.lowtouch.ai
        -t| --targeturl      target endpoint: ex: http://nvdevkit2025a:8080
        -p| --protocol       enable wss protocol, value: wss
        -r| --renew          force-renewal of certificate
        -h| --help           show this usage page
'''
}

SERVER_NAME=""
TARGET_URL=""
PROTO_TYPE=""
RENEW_CERT=""
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -s|--servername) SERVER_NAME="$2"; shift ;;
        -t|--targeturl) TARGET_URL="$2"; shift ;;
        -p|--protocol) PROTO_TYPE="$2"; shift ;;
        -r|--renew) RENEW_CERT="true"; shift ;;
        -h|--help) show_usage; exit 0;;
        *) echo "Unknown parameter passed: $1"; show_usage; exit 1 ;;
    esac
    shift
done

WSS_PROXY_LINES=""
if [[ ! -z "${PROTO_TYPE}" ]]; then
  if [[ "${PROTO_TYPE}" == "wss" ]]; then
    WSS_PROXY_LINES='RewriteEngine On
RewriteCond %{HTTP:Upgrade} websocket [NC]
RewriteCond %{HTTP:Connection} upgrade [NC]
RewriteRule /(.*) ws://'$(echo $TARGET_URL | awk -F/ '{print $3}')'/$1 [P,L]'
  else
    echo "Unsupported protocol type"; show_usage; exit 1
  fi
fi

if [[ -z "${SERVER_NAME}" || -z "${TARGET_URL}" ]]; then show_usage; exit 1; fi

PERSIST_DIR="/appz/data"
PERSIST_FILE="${PERSIST_DIR}/${SERVER_NAME}.conf"

# Handle certificate renewal
if [[ ! -z "${RENEW_CERT}" ]]; then
  if [[ "${RENEW_CERT}" == "true" ]]; then
    certbot certonly --force-renewal --cert-name ${SERVER_NAME} -d ${SERVER_NAME} --agree-tos --apache
    if [[ "$?" != "0" ]]; then
      echo "Certificate renewal failed"
      exit 1
    fi
    exit 0
  fi
fi

# Generate configuration
CONFIG_CONTENT='''<VirtualHost *:443>
    ServerName '${SERVER_NAME}'
    SSLEngine on
    SSLCertificateFile /etc/letsencrypt/'${SERVER_NAME}'/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/'${SERVER_NAME}'/privkey.pem

    ProxyPreserveHost On

    '${WSS_PROXY_LINES}'
    # Regular HTTP proxying
    ProxyPass / '${TARGET_URL}'/
    ProxyPassReverse / '${TARGET_URL}'/

    ErrorLog /appz/log/'${SERVER_NAME}'-error.log
    CustomLog /appz/log/'${SERVER_NAME}'-access.log combined
</VirtualHost>

<VirtualHost *:80>
    ServerName '${SERVER_NAME}'
    Redirect permanent / https://'${SERVER_NAME}'/

    ErrorLog /appz/log/'${SERVER_NAME}'-http-error.log
    CustomLog /appz/log/'${SERVER_NAME}'-http-access.log combined
</VirtualHost>
'''

if [ ! -f "${PERSIST_FILE}" ]; then
  echo "Generating new configuration for ${SERVER_NAME}"
  
  if [ ! -f "/etc/letsencrypt/${SERVER_NAME}/fullchain.pem" ]; then
    certbot --register-unsafely-without-email --apache -n -d ${SERVER_NAME} --agree-tos
    if [ "$?" != "0" ]; then
      echo "Certificate generation failed"
      exit 1
    fi
  fi
  
  mkdir -p "${PERSIST_DIR}"
  echo "${CONFIG_CONTENT}" > "${PERSIST_FILE}"
  
  apache2ctl configtest
  if [ "$?" != "0" ]; then
    echo "Configuration test failed, removing file"
    rm -f "${PERSIST_FILE}"
    exit 1
  fi
else
  echo "Configuration already exists for ${SERVER_NAME} in ${PERSIST_DIR}"
fi
