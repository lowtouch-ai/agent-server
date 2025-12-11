FROM appz/ubuntu:24.04

RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "x86_64" ]; then \
        ARCH="amd64"; \
    elif [ "$ARCH" = "aarch64" ]; then \
        ARCH="arm64"; \
    else \
        echo "Unsupported architecture: $ARCH" && exit 1; \
    fi && \
    curl -L "https://github.com/prometheus/statsd_exporter/releases/download/v0.28.0/statsd_exporter-0.28.0.linux-$ARCH.tar.gz" -o /tmp/statsd_exporter.tar.gz && \
    tar -xvf /tmp/statsd_exporter.tar.gz -C /tmp/ && \
    mv /tmp/statsd_exporter-0.28.0.linux-$ARCH/statsd_exporter /usr/local/bin/ && \
    rm -rf /tmp/statsd_exporter-0.28.0.linux-$ARCH*

ADD supervisor/* /etc/supervisor/conf.d/
ADD scripts/* /appz/scripts/
RUN chmod +x /appz/scripts/*
EXPOSE 8125 9102
ENTRYPOINT ["/usr/bin/supervisord", "-c", "/etc/supervisor/supervisord.conf", "-n"]
