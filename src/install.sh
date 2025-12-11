#!/bin/bash

# Script to build, restart, and configure Vault in AppZ-Images
# Usage: ./install.sh
# Requires VAULT_APPROLE environment variable to be exported before running

set -e  # Exit on error

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

handle_error() {
    log "ERROR: $1"
    exit 1
}

DOCKER_AVAILABLE=true
command -v docker >/dev/null 2>&1 || { log "WARNING: Docker is not installed, skipping Docker-related steps"; DOCKER_AVAILABLE=false; }
command -v ./build.sh >/dev/null 2>&1 || handle_error "build.sh not found"
command -v ./cleanup.sh >/dev/null 2>&1 || handle_error "cleanup.sh not found"
command -v ./run.sh >/dev/null 2>&1 || handle_error "run.sh not found"

if [ -z "$VAULT_APPROLE" ]; then
    handle_error "VAULT_APPROLE environment variable is not set. Please export it before running the script (e.g., export VAULT_APPROLE=ailab)"
fi

BUILD_IMAGES=(
    "ubuntu-22.04"
    "vault-1.16"
    "python-3.11"
    "postgres-13.3"
    "postgres-13.3_master"
    "agentconnector-13.3"
    "ollama-0.5"
    "predict-3.0"
    "agentomatic-3.1"
    "agentvector-0.3"
    "nodeexporter-1.8"
    "cadvisor-0.47"
    "ubuntu-20.04"
    "airflow-2.0"
    "airflowsvr-2.0"
    "airflowsch-2.0"
    "airflowwkr-2.0"
)
RESTART_IMAGES=(
    "vault-1.16"
    "postgres-13.3_master"
    "agentconnector-13.3"
    "ollama-0.5"
    "predict-3.0"
    "agentomatic-3.1"
    "agentvector-0.3"
    "airflowsvr-2.0"
    "airflowsch-2.0"
    "airflowwkr-2.0"
   "nodeexporter-1.8"
    "cadvisor-0.47"
)

get_container_name() {
    local image=$1
    local project=$(basename "$image")
    local container=""

    if [[ $project == *"-"* ]]; then
        container=$(echo "$project" | awk -F'-|_' '{if ($3 == "") print $1; else print $1"_"$3}')
    else
        container="$project"
    fi

    if [ -z "$container" ]; then
        log "ERROR: Failed to determine container name for $project"
        exit 1
    fi

    echo "$container"
    return 0
}

check_container_health() {
    local image=$1
    local container_name=$(basename "$image")
    local base_name=$(get_container_name "$image")
    local max_attempts=30  # 30-second wait (15 × 2s) for health check
    local delay=2
    local attempt=1

    sleep 1

    log "Checking health of $container_name (name: $base_name)..."
    case $container_name in
        "vault-1.16")
            while [ $attempt -le $max_attempts ]; do
                if docker exec "$base_name" vault status >/dev/null 2>&1; then
                    log "Container $container_name (name: $base_name) is healthy"
                    return 0
                fi
                sleep $delay
                ((attempt++))
            done
            ;;
        "postgres-13.3_master")
            while [ $attempt -le $max_attempts ]; do
                if docker logs "$base_name" 2>&1 | grep -q "database system is ready to accept connections"; then
                    log "Container $container_name (name: $base_name) is healthy"
                    return 0
                fi
                sleep $delay
                ((attempt++))
            done
            ;;
	"agentconnector-13.3")
            while [ $attempt -le $max_attempts ]; do
                local http_status=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/webshop/docs)
                if [ "$http_status" -eq 200 ]; then
                    log "Container $container_name (name: $base_name) is healthy (HTTP status: $http_status)"
                    return 0
                fi
                sleep $delay
                ((attempt++))
            done
            ;;
        "ollama-0.5")
            while [ $attempt -le $max_attempts ]; do
                if docker logs "$base_name" 2>&1 | grep -q "Ollama service started successfully"; then
                    log "Container $container_name (name: $base_name) is healthy"
                    return 0
                fi
                sleep $delay
                ((attempt++))
            done
            ;;
        "predict-3.0")  # Added health check for predict-3.0
            while [ $attempt -le $max_attempts ]; do
                if docker logs "$base_name" 2>&1 | grep -q "Watching for changes in UUID-named folders under /appz/data..."; then
                    log "Container $container_name (name: $base_name) is healthy"
                    return 0
                fi
                sleep $delay
                ((attempt++))
            done
            ;;
        "agentomatic-3.1")
            while [ $attempt -le $max_attempts ]; do
                if docker logs "$base_name" 2>&1 | grep -q "Uvicorn running on http://0.0.0.0:8080"; then
                    log "Container $container_name (name: $base_name) is healthy"
                    return 0
                fi
                sleep $delay
                ((attempt++))
            done
            ;;
        "agentvector-0.3")
            while [ $attempt -le $max_attempts ]; do
                local http_status=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/vector/docs)
                if [ "$http_status" -eq 200 ]; then
                    log "Container $container_name (name: $base_name) is healthy (HTTP status: $http_status)"
                    return 0
                fi
                sleep $delay
                ((attempt++))
            done
            ;;
        "airflowsvr-2.0")
            while [ $attempt -le $max_attempts ]; do
                local http_status=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/health)
                if [ "$http_status" -eq 200 ]; then
                    log "Container $container_name (name: $base_name) is healthy (HTTP status: $http_status)"
                    return 0
                fi
                sleep $delay
                ((attempt++))
            done
            ;;
        "airflowsch-2.0")
            while [ $attempt -le $max_attempts ]; do
                if docker logs "$base_name" 2>&1 | grep -q "Starting the scheduler"; then
                    log "Container $container_name (name: $base_name) is healthy"
                    return 0
                fi
                sleep $delay
                ((attempt++))
            done
            ;;
        "airflowwkr-2.0")
            while [ $attempt -le $max_attempts ]; do
                if docker logs "$base_name" 2>&1 | grep -q "celery worker ready"; then
                    log "Container $container_name (name: $base_name) is healthy"
                    return 0
                fi
                sleep $delay
                ((attempt++))
            done
            ;;
        *)
            log "ERROR: No health check defined for $container_name (name: $base_name)"
            exit 1
            ;;
	"nodeexporter-1.8")
            while [ $attempt -le $max_attempts ]; do
                local http_status=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:9100/metrics)
                if [ "$http_status" -eq 200 ]; then
                    log "Container $container_name (name: $base_name) is healthy (HTTP status: $http_status)"
                    return 0
                fi
                sleep $delay
                ((attempt++))
            done
            ;;
        "cadvisor-0.47")
            while [ $attempt -le $max_attempts ]; do
                local http_status=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/metrics)
                if [ "$http_status" -eq 200 ]; then
                    log "Container $container_name (name: $base_name) is healthy (HTTP status: $http_status)"
                    return 0
                fi
                sleep $delay
                ((attempt++))
            done
            ;;
    esac

    log "ERROR: Container $container_name (name: $base_name) failed health check after $((max_attempts * delay)) seconds"
    exit 1
}

if [ "$DOCKER_AVAILABLE" = true ]; then
    log "Starting Docker image builds..."
    for image in "${BUILD_IMAGES[@]}"; do
        log "Building $image..."
        if [ ! -d "$image" ]; then
            handle_error "Directory $image does not exist"
        fi
        (cd "$image" && ../build.sh) || handle_error "Failed to build $image"
    done

    log "Processing Vault container..."
    if [ ! -d "vault-1.16" ]; then
        handle_error "Directory vault-1.16 does not exist"
    fi
    log "Cleaning up existing vault container..."
    (cd vault-1.16 && ../cleanup.sh) || log "Warning: Failed to clean up vault container, proceeding"
    log "Running vault-1.16 container..."
    (cd vault-1.16 && ../run.sh) || handle_error "Failed to run vault-1.16 container"
    check_container_health "vault-1.16"

    log "Configuring Vault..."
    VAULT_CONTAINER=$(docker ps -q -f name=vault)
    if [ -z "$VAULT_CONTAINER" ]; then
        handle_error "Vault container not found"
    fi

    log "Waiting for Vault container to be ready..."
    for i in {1..30}; do
        if docker exec "$VAULT_CONTAINER" vault status >/dev/null 2>&1; then
            break
        fi
        sleep 2
    done

    if ! docker exec "$VAULT_CONTAINER" vault status >/dev/null 2>&1; then
        handle_error "Vault container not ready after timeout"
    fi

    if [ -f ~/.appz/init.conf ] && [ -s ~/.appz/init.conf ]; then
        log "AppRole configuration already exists at ~/.appz/init.conf, checking contents..."
    else
        log "Generating AppRole..."
        APPROLE_OUTPUT=$(docker exec "$VAULT_CONTAINER" bash -c "cd /appz/scripts && ./get_approle.sh $VAULT_APPROLE" 2>&1)
        if [ $? -ne 0 ]; then
            log "AppRole generation output: $APPROLE_OUTPUT"
            handle_error "Failed to generate AppRole"
        fi

        log "Writing AppRole configuration to VM..."
        mkdir -p ~/.appz || handle_error "Failed to create ~/.appz directory"

        VAULT_ROLE_ID=$(echo "$APPROLE_OUTPUT" | grep "VAULT_ROLE_ID=" | awk -F'=' '{print $2}' | head -n 1)
        VAULT_SECRET_ID=$(echo "$APPROLE_OUTPUT" | grep "VAULT_SECRET_ID=" | awk -F'=' '{print $2}' | head -n 1)

        if [ -z "$VAULT_ROLE_ID" ] || [ -z "$VAULT_SECRET_ID" ]; then
            log "AppRole generation output: $APPROLE_OUTPUT"
            handle_error "Failed to extract VAULT_ROLE_ID or VAULT_SECRET_ID from get_approle.sh output"
        fi

        cat << EOF > ~/.appz/init.conf
export VAULT_APPROLE=$VAULT_APPROLE
export VAULT_ROLE_ID=$VAULT_ROLE_ID
export VAULT_SECRET_ID=$VAULT_SECRET_ID
EOF
        if [ $? -ne 0 ]; then
            handle_error "Failed to write AppRole configuration to ~/.appz/init.conf"
        fi
        log "AppRole configuration written to ~/.appz/init.conf"
    fi

    log "Checking AppRole configuration in ~/.appz/init.conf..."
    VAULT_APPROLE_CHECK=$(grep "export VAULT_APPROLE=" ~/.appz/init.conf | cut -d'=' -f2)
    VAULT_ROLE_ID_CHECK=$(grep "export VAULT_ROLE_ID=" ~/.appz/init.conf | cut -d'=' -f2)
    VAULT_SECRET_ID_CHECK=$(grep "export VAULT_SECRET_ID=" ~/.appz/init.conf | cut -d'=' -f2)

    if [ -n "$VAULT_APPROLE_CHECK" ] && [ -n "$VAULT_ROLE_ID_CHECK" ] && [ -n "$VAULT_SECRET_ID_CHECK" ]; then
        log "AppRole configuration verified in ~/.appz/init.conf:"
        log "VAULT_APPROLE=$VAULT_APPROLE_CHECK"
        log "VAULT_ROLE_ID=$VAULT_ROLE_ID_CHECK"
        log "VAULT_SECRET_ID=$VAULT_SECRET_ID_CHECK"
    else
        handle_error "Required variables missing in ~/.appz/init.conf. Found: VAULT_APPROLE=$VAULT_APPROLE_CHECK, VAULT_ROLE_ID=$VAULT_ROLE_ID_CHECK, VAULT_SECRET_ID=$VAULT_SECRET_ID_CHECK"
    fi

    log "Restarting remaining containers..."
    for image in "${RESTART_IMAGES[@]}"; do
        if [ "$image" != "vault-1.16" ]; then
            log "Processing container for $image..."
            if [ ! -d "$image" ]; then
                handle_error "Directory $image does not exist"
            fi
            log "Cleaning up existing $image container..."
            (cd "$image" && ../cleanup.sh) || log "Warning: Failed to clean up $image container, proceeding"
            log "Running $image container..."
            (cd "$image" && ../run.sh) || handle_error "Failed to run $image container"
            check_container_health "$image"
        fi
    done
else
    log "Skipping Docker image builds, container restarts, and Vault configuration due to missing Docker"
fi

log "Image building, Vault configuration, and container restarting completed successfully!"
