FROM redis:bookworm

RUN apt-get update && apt-get install -y curl jq cron supervisor sendmail gnupg uuid-runtime logrotate wget
RUN curl -sL 'https://packages.treasuredata.com/GPG-KEY-td-agent' | gpg --dearmor -o /etc/apt/trusted.gpg.d/treasure-data.gpg && echo "deb http://deb.debian.org/debian stable main" >> /etc/apt/sources.list
RUN apt-get update && apt-get install zlib1g python3-aiohttp python3.11 linux-libc-dev systemd -y
VOLUME /appz/log
VOLUME /appz/home
VOLUME /appz/cache
VOLUME /appz/data
VOLUME /appz/backup
VOLUME /var/run/redis

ADD supervisor/cron.conf /etc/supervisor/conf.d/cron.conf
ADD scripts /appz/scripts

ENV HOME=/appz/home
#fluentd installation
ADD scripts/fluentd.sh /usr/local/bin/fluentd.sh
RUN bash /usr/local/bin/fluentd.sh
ADD conf/fluentd.conf /etc/fluent/fluent.conf
ADD plugin/out_graylog.rb /etc/fluent/plugin/out_graylog.rb
ADD supervisor/supervisord.conf /etc/supervisor/supervisord.conf
ADD scripts/fluentd_run.sh /appz/scripts/fluentd_run.sh
ADD supervisor/fluentd.conf /etc/supervisor/conf.d/fluentd.conf
ADD supervisor/redis.conf /etc/supervisor/conf.d/redis.conf
ADD supervisor/adduser.conf /etc/supervisor/conf.d/adduser.conf
ADD supervisor/tail.conf /etc/supervisor/conf.d/tail.conf
ADD supervisor/redis_exporter.conf /etc/supervisor/conf.d/redis_exporter.conf
ADD scripts/archive.sh /appz/scripts/
ADD scripts/logrotate.sh /appz/scripts/
RUN chmod +x /appz/scripts/*
ADD conf/logrotate.conf /etc/logrotate.d/logrotate.conf
RUN chmod 644 /etc/logrotate.d/logrotate.conf
ADD conf/redis.conf /usr/local/etc/redis/redis.conf
WORKDIR /appz/data
RUN crontab -l | { cat; echo "0 4 * * * /bin/bash -c  /appz/scripts/logrotate.sh"; } | crontab - \
    && crontab -l | { cat;  echo "@reboot  /bin/bash -c  /appz/scripts/archive.sh"; } | crontab - \
    && crontab -l | { cat;  echo "*/15 * * * * /bin/bash -c  /appz/scripts/cleanup.sh"; } | crontab -
RUN echo 'alias ctl="supervisorctl"' >> /appz/.bashrc \ 
	&& echo 'alias status="supervisorctl status"' >> /appz/.bashrc \ 
	&& echo 'alias start="supervisorctl start"' >> /appz/.bashrc \
	&& echo 'alias stop="supervisorctl stop"' >> /appz/.bashrc \
	&& echo 'alias restart="supervisorctl restart"' >> /appz/.bashrc \
	&& echo 'alias dev="cd /appz/dev"' >> /appz/.bashrc \
	&& echo 'alias scripts="cd /appz/scripts"' >> /appz/.bashrc \
	&& echo 'alias log="cd /appz/log"' >> /appz/.bashrc \ 
	&& echo 'alias cache="cd /appz/cache"' >> /appz/.bashrc \ 
	&& echo 'alias data="cd /appz/data"' >> /appz/.bash
### Add redis_exporter
RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "x86_64" ]; then \
        ARCH="amd64"; \
    elif [ "$ARCH" = "aarch64" ]; then \
        ARCH="arm64"; \
    else \
        echo "Unsupported architecture: $ARCH" && exit 1; \
    fi && \
    curl -L "https://github.com/oliver006/redis_exporter/releases/download/v1.44.0/redis_exporter-v1.44.0.linux-$ARCH.tar.gz" -o /tmp/redis_exporter.tar.gz && \
    tar xvf /tmp/redis_exporter.tar.gz -C /tmp/ && \
    mv /tmp/redis_exporter-*.linux-$ARCH/redis_exporter /usr/local/bin/ && \
    rm -rf /tmp/redis_exporter-*.linux-$ARCH*
EXPOSE 9121

ENTRYPOINT ["/usr/bin/supervisord", "-c", "/etc/supervisor/supervisord.conf", "-n"]
HEALTHCHECK --interval=1m --timeout=3s \
        CMD  bash -c "supervisorctl pid " || exit 1
