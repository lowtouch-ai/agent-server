FROM appz/ubuntu:24.04

RUN apt-get update && apt-get install -y wget

# Detect architecture and download correct MinIO server package
RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "aarch64" ]; then \
        echo "Downloading ARM64 MinIO"; \
        MINIO_URL="https://dl.min.io/server/minio/release/linux-arm64/archive/minio_20250907161309.0.0_arm64.deb"; \
    else \
        echo "Downloading AMD64 MinIO"; \
        MINIO_URL="https://dl.min.io/server/minio/release/linux-amd64/archive/minio_20250907161309.0.0_amd64.deb"; \
    fi && \
    wget $MINIO_URL -O minio.deb && dpkg -i minio.deb

# Detect architecture and download correct mc client
RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "aarch64" ]; then \
        echo "Downloading ARM64 mc client"; \
        MC_URL="https://dl.min.io/client/mc/release/linux-arm64/mc"; \
    else \
        echo "Downloading AMD64 mc client"; \
        MC_URL="https://dl.min.io/client/mc/release/linux-amd64/mc"; \
    fi && \
    wget $MC_URL -O mc && chmod +x mc && mv mc /usr/local/bin/

COPY supervisor/minio.conf /etc/supervisor/conf.d
COPY scripts/ /appz/scripts
RUN chmod +x /appz/scripts/minio.sh

