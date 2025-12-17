FROM appz/ubuntu:24.04

RUN apt-get update -y && apt-get install -y wget tar

RUN ARCH=$(uname -m) \
    && if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then \
         PROM_ARCH="linux-arm64"; \
       else \
         PROM_ARCH="linux-amd64"; \
       fi \
    && wget https://github.com/prometheus/prometheus/releases/download/v3.6.0/prometheus-3.6.0.$PROM_ARCH.tar.gz -O prometheus.tar.gz \
    && tar -xzf prometheus.tar.gz \
    && mv prometheus-3.6.0.$PROM_ARCH/prometheus /usr/local/bin/ \
    && mv prometheus-3.6.0.$PROM_ARCH/promtool /usr/local/bin/ \
    && mkdir -p /etc/prometheus /var/lib/prometheus \
    && rm -rf prometheus-3.6.0.* prometheus.tar.gz
ADD scripts /appz/scripts
RUN chmod +x /appz/scripts/*

ADD scripts/prometheus.yaml /etc/prometheus/
ADD scripts/rules.yaml /etc/prometheus/
ADD scripts/alerts.yaml /etc/prometheus/
ADD scripts/start.sh /appz/scripts/
RUN chmod +x /appz/scripts/start.sh

ADD supervisor/prometheus.conf /etc/supervisor/conf.d/

EXPOSE 9090

ENTRYPOINT ["/usr/bin/supervisord", "-c", "/etc/supervisor/supervisord.conf", "-n"]

HEALTHCHECK --interval=1m --timeout=3s \
    CMD bash -c "supervisorctl pid" || exit 1

