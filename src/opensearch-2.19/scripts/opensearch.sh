#!/bin/bash

OS_CONFIG_FILE="/usr/share/opensearch/config/opensearch.yml"

if [ -z "$NODE_MODE" ] || [ "$NODE_MODE" == "single-node" ]; then
    if ! grep -qE "^\s*discovery.type:\s*single-node$" "$OS_CONFIG_FILE"; then
        sed -i "/discovery.type:/d" "$OS_CONFIG_FILE"  # Remove existing entries
        sed -i "\$a discovery.seed_hosts: []" "$OS_CONFIG_FILE"
        sed -i "\$a discovery.type: single-node" "$OS_CONFIG_FILE"  # Append new entry at the end
    fi

fi

if [[ "$NODE_MODE" == "multi-node" ]]; then
    POD=$(echo $HOSTNAME | awk -F "-" '{print $NF}')
    host=$(echo $HOSTNAME | awk -F "-" '{OFS="-"; $NF=""; sub(/-$/, "", $0); print}')
    if [[ "$POD" == "0" ]]; then
        if ! grep -qF "node.name: $HOSTNAME" "$OS_CONFIG_FILE"; then
            sed -i "\$a node.name: $HOSTNAME" "$OS_CONFIG_FILE"
            var=""
            sep=""
            for (( i=0; i<$REPLICA_COUNT; i++ )); do
                var+="${sep}\"${host}-${i}.${host}\""
                sep=", "
            done
            var1="[$var]"
            sed -i "\$a discovery.seed_hosts: $var1" "$OS_CONFIG_FILE"
            sed -i "\$a cluster.initial_cluster_manager_nodes: [\"${host}-0\"]" "$OS_CONFIG_FILE"
        fi
    elif [[ "$POD" != "0" ]]; then
        if ! grep -qF "node.name: $HOSTNAME" "$OS_CONFIG_FILE"; then
            sed -i "\$a node.name: $HOSTNAME" "$OS_CONFIG_FILE"
            var=""
            sep=""
            for (( i=0; i<$REPLICA_COUNT; i++ )); do
                var+="${sep}\"${host}-${i}.${host}\""
                sep=", "
            done
            var1="[$var]"
            sed -i "\$a discovery.seed_hosts: $var1" "$OS_CONFIG_FILE"
            sed -i "\$a cluster.initial_cluster_manager_nodes: [\"${host}-0\"]" "$OS_CONFIG_FILE"
        fi
    else
        echo "Node selection not occurred"
    fi
fi

# Checking for JVM options file, update the initial and maximum size of the total heap space.
jvm_file="/usr/share/opensearch/config/jvm.options"
if [[ -e $jvm_file ]]; then
    echo "JVM options file exists"
    if [[ -n "$JAVA_HEAPSIZE" ]]; then
        sed -i "s/^\\s*-Xms.*/-Xms$JAVA_HEAPSIZE/" "$jvm_file"
        sed -i "s/^\\s*-Xmx.*/-Xmx$JAVA_HEAPSIZE/" "$jvm_file"
    else
        echo "ENV JAVA_HEAPSIZE is not set, Going with the default value"
    fi
else
    echo "JVM options file doesn't exist"
fi

# Your environment variable check and Vault integration
if env | grep -q "VAULT:"; then
   c=1
   mc=180
   while ! curl -k -o /dev/null -s -w "%{http_code}\n" -k $VAULT_ADDR/v1/sys/health | grep -q "200"; do
       echo "waiting for $VAULT_ADDR..."
       sleep 1
       ((c++))
       if [ $c -gt $mc ]; then
           echo "FATAL: vault timeout... exiting"
           exit 1
       fi
   done
   VAULT_GET_ADDR=$(echo $VAULT_ADDR | awk -F ':' '{print $1":"$2}' | sed 's/https/http/g')
   source <(curl -s $VAULT_GET_ADDR/get_secret.sh)
fi

kill_opensearch() {
    echo "Checking for existing OpenSearch processes..."
    pids=$(ps aux | awk '/share/ && !/scripts/ {print $2}') 
    if [[ -n "$pids" ]]; then
        echo "Killing all existing OpenSearch processes..."
        echo $pids | xargs kill
        sleep 5  # Wait for 5 seconds to ensure the processes have terminated
        echo "Processes terminated."
    else
        echo "No OpenSearch processes found."
    fi
}
kill_opensearch

if [ ${ENABLE_METRICS:-0} = 1 ]; then
    echo "Prometheus metrics enabled for OpenSearch"
    if ! opensearch-plugin list | grep -q 'prometheus-exporter'; then
        echo "installing prometheus exporter plugin"
	./bin/opensearch-plugin install file:///tmp/prometheus-exporter.zip
    else
        echo "Prometheus exporter plugin is already installed"
    fi
fi

if [[ -z "$MINIO_ACCESS_KEY" || -z "$MINIO_SECRET_KEY" || -z "$MINIO_ENDPOINT" || -z "$MINIO_BUCKET_NAME" ]]; then
    echo "MINIO Credentials are missing, skipping minio initialization"
else
    printf "$MINIO_ACCESS_KEY\n" | /usr/share/opensearch/bin/opensearch-keystore add --stdin s3.client.default.access_key -f
    printf "$MINIO_SECRET_KEY\n" | /usr/share/opensearch/bin/opensearch-keystore add --stdin s3.client.default.secret_key -f
    echo "MINIO keys added to OpenSearch keystore."
fi

echo "Starting OpenSearch..."
exec /usr/share/opensearch/opensearch-docker-entrypoint.sh
