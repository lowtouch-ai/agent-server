FROM ghcr.io/google/cadvisor:latest
USER root
RUN apk add --no-cache bash
RUN apk update \
    && apk add --no-cache curl zip jq python3 python3-dev apk-cron supervisor logrotate \
    && mkdir -p /appz/log/supervisor
VOLUME /appz/log
VOLUME /appz/home
VOLUME /appz/cache
VOLUME /appz/data
VOLUME /appz/backup
VOLUME /appz/keys

RUN mkdir -p  /var/lib/logrotate/

RUN apk add logrotate
ADD scripts /appz/scripts
ADD conf/logrotate.conf /etc/logrotate.d/
RUN chmod 644 /etc/logrotate.d/logrotate.conf

ADD supervisor/supervisord.conf /etc/supervisor/supervisord.conf
ADD supervisor/dockerexporter.conf /etc/supervisor/conf.d/dockerexporter.conf
ADD supervisor/cron.conf /etc/supervisor/conf.d/cron.conf
ADD supervisor/logrotate.conf /etc/supervisor/conf.d/logrotate.conf
ADD supervisor/* /etc/supervisor/conf.d/
RUN chmod +x /appz/scripts/*.sh \
        && crontab -r | { cat; echo "* */3 * * * /bin/bash -c  /appz/scripts/logrotate.sh"; } | crontab - \
        && crontab -l | { cat; echo "@reboot  mkdir -p /appz/log/archive "; } | crontab - \
        && crontab -l | { cat;  echo "*/15 * * * * /bin/bash -c  /appz/scripts/cleanup.sh"; } | crontab -

RUN echo 'alias ctl="supervisorctl"' >> /appz/.bashrc \
        && echo 'alias status="supervisorctl status"' >> /appz/.bashrc \
        && echo 'alias start="supervisorctl start"' >> /appz/.bashrc \
        && echo 'alias stop="supervisorctl stop"' >> /appz/.bashrc \
        && echo 'alias restart="supervisorctl restart"' >> /appz/.bashrc \
        && echo 'alias dev="cd /appz/dev"' >> /appz/.bashrc \
        && echo 'alias scripts="cd /appz/scripst"' >> /appz/.bashrc \
        && echo 'alias log="cd /appz/log"' >> /appz/.bashrc \
        && echo 'alias cache="cd /appz/cache"' >> /appz/.bashrc \
        && echo 'alias data="cd /appz/data"' >> /appz/.bashrc

ENTRYPOINT ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf", "-n"]
HEALTHCHECK --interval=1m --timeout=3s \
        CMD  bash -c "supervisorctl pid " || exit 1
