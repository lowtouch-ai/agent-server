FROM mongo:8.0

RUN mkdir -p  /appz/log/ /appz/data/ \
    && touch /appz/log/supervisord.log
VOLUME /appz/log
VOLUME /appz/home
VOLUME /appz/cache
VOLUME /appz/data
VOLUME /appz/backup

RUN apt-get update && apt-get install -y supervisor cron gcc make logrotate bc curl net-tools uuid-runtime zip mongodb-mongosh
RUN apt-get update -y && apt-get install -y python3 python3-pip python3-venv
RUN python3 -m venv /appz/venv \
    && /appz/venv/bin/pip install --upgrade pip \
    && /appz/venv/bin/pip install pymongo pyyaml pytz python-dotenv boto3 \
    && /appz/venv/bin/pip install awscli --upgrade
ENV PATH="/appz/venv/bin:$PATH"
ADD supervisor/supervisord.conf /etc/supervisor/supervisord.conf
ADD supervisor/cron.conf /etc/supervisor/conf.d/cron.conf
ADD scripts/fluentd.sh /usr/local/bin/fluentd.sh
ADD conf/fluentd.conf /etc/td-agent/td-agent.conf
RUN sh /usr/local/bin/fluentd.sh
ADD conf/fluentd.conf /etc/fluent/fluentd.conf
ADD scripts/fluentd_run.sh /appz/scripts/fluentd_run.sh
ADD plugin/out_graylog.rb /etc/fluent/plugin/out_graylog.rb
RUN /usr/sbin/fluent-gem install fluent-plugin-grok-parser
ADD supervisor/fluentd.conf /etc/supervisor/conf.d/fluentd.conf
ADD supervisor/mongo_addusers.conf /etc/supervisor/conf.d/mongo_addusers.conf
ADD supervisor/mongo_supervisor.conf  /etc/supervisor/conf.d/mongo_supervisor.conf
ADD supervisor/mongo_exporter.conf  /etc/supervisor/conf.d/mongo_exporter.conf
ADD supervisor/mongo_backup.conf /etc/supervisor/conf.d/mongo_backup.conf
WORKDIR /opt/
RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "x86_64" ]; then \
        EXPORTER_URL="https://github.com/percona/mongodb_exporter/releases/download/v0.44.0/mongodb_exporter-0.44.0.linux-amd64.tar.gz"; \
    elif [ "$ARCH" = "aarch64" ]; then \
        EXPORTER_URL="https://github.com/percona/mongodb_exporter/releases/download/v0.44.0/mongodb_exporter-0.44.0.linux-arm.tar.gz"; \
    else \
        echo "Unsupported architecture: $ARCH" && exit 1; \
    fi && \
    echo "Downloading MongoDB Exporter for $ARCH..." && \
    curl -L -o mongodb_exporter.tar.gz "$EXPORTER_URL" && \
    tar -xzf mongodb_exporter.tar.gz && \
    cp mongodb_exporter-*/mongodb_exporter /usr/local/bin/ && \
    rm -rf mongodb_exporter* mongodb_exporter.tar.gz
ADD scripts /appz/scripts
RUN chmod +x /appz/scripts/addusers.sh
RUN chmod +x /appz/scripts/prepare.sh
RUN chmod +x /appz/scripts/activate_mongo.py
RUN chmod +x /appz/scripts/mongoexporter.sh
RUN chmod +x /appz/scripts/mongo_backup.sh
RUN chmod +x /appz/scripts/backup.py
RUN chmod +x /appz/scripts/restore.sh

ADD conf/logrotate.conf /etc/logrotate.d/logrotate.conf
ADD conf/mongod.conf /etc/mongod.conf
ADD scripts/mongo_contents /appz/scripts/mongo_contents
RUN chmod 644 /etc/logrotate.d/logrotate.conf
RUN apt-get update -y && apt-get install -y python3 python3-pip
RUN pip3 install awscli --upgrade

RUN echo "*/15 * * * * /usr/bin/nice -5 bash /appz/scripts/cleanup.sh" | crontab - \
    && crontab -l | { cat;  echo "@reboot  /bin/bash  /appz/scripts/archive.sh"; } | crontab - \
    && crontab -l | { cat; echo "0 4 * * * /bin/bash   /appz/scripts/logrotate.sh"; } | crontab -

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
EXPOSE 9216
RUN bash -c "/appz/scripts/prepare.sh /appz/scripts/mongo_contents/"

ENTRYPOINT ["/usr/bin/supervisord", "-c", "/etc/supervisor/supervisord.conf", "-n"]
HEALTHCHECK --interval=1m --timeout=3s \
        CMD  bash -c "supervisorctl pid " || exit 1
