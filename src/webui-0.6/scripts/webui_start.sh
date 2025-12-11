#!/usr/bin/env bash
#!/bin/bash
# Activate backend's isolated environment
source /app/backend/venv/bin/activate
export PATH="/app/backend/venv/bin:$PATH"

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

# Redirect all stdout & stderr through `ts` to add timestamps
exec > >(ts '[%Y-%m-%d %H:%M:%S]') 2>&1

DIR="/appz/data/webui"

if [ -d "$DIR" ]; then
    echo "Directory $DIR exists."
else
    echo "Directory $DIR does not exist. Creating..."
    mkdir -p "$DIR"
    if [ $? -eq 0 ]; then
        echo "Directory $DIR created successfully."
    else
        echo "Failed to create directory $DIR."
        exit 1
    fi
fi

chmod -R 777 /appz/data/
cd /app/backend
#SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
#cd "$SCRIPT_DIR" || exit

KEY_FILE=.webui_secret_key

PORT="${PORT:-8080}"
HOST="${HOST:-0.0.0.0}"
if test "$WEBUI_SECRET_KEY $WEBUI_JWT_SECRET_KEY" = " "; then
  echo "Loading WEBUI_SECRET_KEY from file, not provided as an environment variable."

  if ! [ -e "$KEY_FILE" ]; then
    echo "Generating WEBUI_SECRET_KEY"
    echo $(head -c 12 /dev/random | base64) > "$KEY_FILE"
  fi

  echo "Loading WEBUI_SECRET_KEY from $KEY_FILE"
  WEBUI_SECRET_KEY=$(cat "$KEY_FILE")
fi

if [[ "${USE_OLLAMA_DOCKER,,}" == "true" ]]; then
    echo "USE_OLLAMA is set to true, starting ollama serve."
    ollama serve &
fi

if [[ "${USE_CUDA_DOCKER,,}" == "true" ]]; then
  echo "CUDA is enabled, appending LD_LIBRARY_PATH to include torch/cudnn & cublas libraries."
  export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:/usr/local/lib/python3.11/site-packages/torch/lib:/usr/local/lib/python3.11/site-packages/nvidia/cudnn/lib"
fi

ENABLE_CODE_INTERPRETER="${ENABLE_CODE_INTERPRETER:-false}"
# Just to confirm value (optional for debugging)
echo "ENABLE_CODE_INTERPRETER is set to: $ENABLE_CODE_INTERPRETER"

if [ -z "$OPENWEBUI_POSTGRES_USER" ] || [ -z "$OPENWEBUI_POSTGRES_PASSWORD" ] || [ -z "$OPENWEBUI_POSTGRES_DATABASE" ]; then
    echo "Warning: Missing required PostgreSQL environment variables (OPENWEBUI_POSTGRES_USER, OPENWEBUI_POSTGRES_PASSWORD, OPENWEBUI_POSTGRES_DATABASE)"
else
    DATABASE_URL="postgresql://${OPENWEBUI_POSTGRES_USER}:${OPENWEBUI_POSTGRES_PASSWORD}@postgres:5432/${OPENWEBUI_POSTGRES_DATABASE}"
    export DATABASE_URL
fi

# Check if SPACE_ID is set, if so, configure for space
if [ -n "$SPACE_ID" ]; then
  echo "Configuring for HuggingFace Space deployment"
  if [ -n "$ADMIN_USER_EMAIL" ] && [ -n "$ADMIN_USER_PASSWORD" ]; then
    echo "Admin user configured, creating"
    WEBUI_SECRET_KEY="$WEBUI_SECRET_KEY" uvicorn open_webui.main:app --host "$HOST" --port "$PORT" --forwarded-allow-ips '*' &
    webui_pid=$!
    echo "Waiting for webui to start..."
    while ! curl -s http://localhost:8080/health > /dev/null; do
      sleep 1
    done
    echo "Creating admin user..."
    curl \
      -X POST "http://localhost:8080/api/v1/auths/signup" \
      -H "accept: application/json" \
      -H "Content-Type: application/json" \
      -d "{ \"email\": \"${ADMIN_USER_EMAIL}\", \"password\": \"${ADMIN_USER_PASSWORD}\", \"name\": \"Admin\" }"
    echo "Shutting down webui..."
    kill $webui_pid
  fi

  export WEBUI_URL=${SPACE_HOST}
fi

echo "Starting OpenWebUI..."
WEBUI_SECRET_KEY="$WEBUI_SECRET_KEY" exec uvicorn open_webui.main:app --host "$HOST" --port "$PORT" --forwarded-allow-ips '*' --reload
