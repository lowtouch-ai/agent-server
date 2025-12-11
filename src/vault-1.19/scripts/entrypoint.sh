#!/bin/bash
if [ $ENABLE_UI == True ]
then
    echo "enabling Vault UI ... "
    sed -i '2 i \        "ui": "true",' /vault/config/local.json
fi
exec vault server -config /vault/config/local.json
