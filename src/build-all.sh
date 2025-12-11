#!/bin/bash

cwd=$(pwd)
images=( ubuntu-20.04 ubuntu-22.04 python-3.11 vault-1.16 postgres-13.3 postgres-13.3_master agentconnector-13.3 ollama-0.5 predict-3.0 agentvector-0.3 agentomatic-3.1 airflow-2.0 redis-8.0 airflowsvr-2.0 airflowsch-2.0 airflowwkr-2.0 gitrunner-2.0 cadvisor-0.47 airflowexporter-0.26 mongo-6.0 opensearch-2.13 graylog-5.2 blackboxexporter-0.25 prometheus-2.54 grafana-11.2 )

for i in "${images[@]}"
do
    echo "----------------------- Building $i -----------------------"
    if ! cd "$i" 2>/dev/null; then
        echo "Error: Directory $i does not exist"
        cd "$cwd" || exit 1
        exit 1
    fi
    echo "Current directory: $(pwd)"

    find . -type f -exec dos2unix {} \; 2>/dev/null
    if [ $? -ne 0 ]; then
        echo "Warning: Non-text files in $i have skipped dos2unix conversion"
    fi

    if ! bash -c "../build.sh $i"; then
        echo "Error: Failed to build $i"
        cd "$cwd" || exit 1
        exit 1
    fi
    cd "$cwd" || exit 1
done

echo "All builds completed successfully"
cd "$cwd" || exit 1
