FROM graylog/graylog:7.0.0

USER root

VOLUME /appz/log
VOLUME /appz/home
VOLUME /appz/cache
VOLUME /appz/data
VOLUME /appz/backup

RUN ARCH=$(uname -m) && \
    echo "Detected architecture: $ARCH" && \
    if [ "$ARCH" = "x86_64" ]; then \
        echo "x86_64 → using archive.ubuntu.com"; \
        BASE="http://archive.ubuntu.com/ubuntu"; \
        SEC="http://security.ubuntu.com/ubuntu"; \
    elif [ "$ARCH" = "aarch64" ]; then \
        echo "aarch64 → using ports.ubuntu.com (ARM64 repository)"; \
        BASE="http://ports.ubuntu.com/ubuntu-ports"; \
        SEC="http://ports.ubuntu.com/ubuntu-ports"; \
    else \
        echo "Unsupported arch: $ARCH" && exit 1; \
    fi && \
    printf "deb $BASE noble main restricted\n"              > /etc/apt/sources.list && \
    printf "deb $BASE noble-updates main restricted\n"     >> /etc/apt/sources.list && \
    printf "deb $SEC noble-security main restricted\n"     >> /etc/apt/sources.list && \
    printf "deb $BASE noble universe\n"                    >> /etc/apt/sources.list && \
    printf "deb $BASE noble-updates universe\n"            >> /etc/apt/sources.list && \
    printf "deb $SEC noble-security universe\n"            >> /etc/apt/sources.list && \
    printf "deb $BASE noble multiverse\n"                  >> /etc/apt/sources.list && \
    printf "deb $BASE noble-updates multiverse\n"          >> /etc/apt/sources.list && \
    printf "deb $SEC noble-security multiverse\n"          >> /etc/apt/sources.list && \
    printf "deb $BASE noble-backports main restricted universe multiverse\n" >> /etc/apt/sources.list


RUN apt-get update && apt-get install -y --no-install-recommends \
    supervisor cron curl jq logrotate python3 python3-pip python3-venv \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN python3 -m venv /appz/venv \
    && /appz/venv/bin/pip install --upgrade pip \
    && /appz/venv/bin/pip install minio

ENV PATH="/appz/venv/bin:$PATH"


ADD supervisor/supervisord.conf /etc/supervisor/supervisord.conf
ADD supervisor/cron.conf        /etc/supervisor/conf.d/cron.conf
ADD supervisor/graylog.conf     /etc/supervisor/conf.d/graylog.conf
ADD supervisor/tail.conf        /etc/supervisor/conf.d/tail.conf
ADD supervisor/minio_backup.conf /etc/supervisor/conf.d/minio_backup.conf


ADD conf/log4j2.xml       /usr/share/graylog/data/config/log4j2.xml
ADD conf/logrotate.conf   /etc/logrotate.d/logrotate.conf
RUN chmod 644 /etc/logrotate.d/logrotate.conf


ADD scripts /appz/scripts
RUN chmod +x /appz/scripts/*.sh \
    && echo "*/15 * * * * /bin/nice -5 /appz/scripts/cleanup.sh" | crontab - \
    && crontab -l | { cat; echo "@reboot chown -R graylog:graylog /usr/share/graylog/data"; } | crontab - \
    && crontab -l | { cat; echo "0 4 * * * /bin/bash -c /appz/scripts/logrotate.sh"; } | crontab - \
    && crontab -l | { cat; echo "@reboot /bin/bash -c /appz/scripts/archive.sh"; } | crontab -

ENTRYPOINT ["/usr/bin/supervisord", "-c", "/etc/supervisor/supervisord.conf", "-n"]
