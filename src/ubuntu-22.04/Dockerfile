FROM ubuntu:22.04

# Install dependencies
RUN apt-get update -y \
	&& apt-get install -y git curl zip jq cron supervisor sendmail gnupg uuid-runtime python3 python3-pip logrotate

VOLUME /appz/log
VOLUME /appz/home
VOLUME /appz/cache
VOLUME /appz/data
VOLUME /appz/backup

ADD supervisor/cron.conf /etc/supervisor/conf.d/cron.conf
ADD scripts /appz/scripts

ENV HOME=/appz/home
#fluentd installation
ADD scripts/fluentd.sh /usr/local/bin/fluentd.sh
RUN sh /usr/local/bin/fluentd.sh
ADD conf/fluentd.conf /etc/td-agent/td-agent.conf
ADD plugin/out_graylog.rb /etc/td-agent/plugin/out_graylog.rb
RUN /usr/sbin/td-agent-gem install fluent-plugin-grok-parser
ADD supervisor/supervisord.conf /etc/supervisor/supervisord.conf
ADD scripts/fluentd_run.sh /appz/scripts/fluentd_run.sh
ADD supervisor/fluentd.conf /etc/supervisor/conf.d/fluentd.conf
ADD supervisor/tail.conf /etc/supervisor/conf.d/tail.conf
ADD scripts/archive.sh /appz/scripts/
ADD scripts/logrotate.sh /appz/scripts/
ADD scripts/sonarqube_scan.sh /appz/scripts/
COPY scripts/prepare.sh /appz/scripts/
RUN chmod +x /appz/scripts/*
ADD conf/logrotate.conf /etc/logrotate.d/logrotate.conf
RUN chmod 644 /etc/logrotate.d/logrotate.conf
RUN crontab -l | { cat; echo "0 4 * * * /bin/bash -c  /appz/scripts/logrotate.sh"; } | crontab - \
    && crontab -l | { cat;  echo "@reboot  /bin/bash -c  /appz/scripts/archive.sh"; } | crontab - \
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

ENTRYPOINT ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/supervisord.conf"]
HEALTHCHECK --interval=1m --timeout=3s \
        CMD  bash -c "supervisorctl pid " || exit 1
