FROM grafana/grafana:12.0.2-ubuntu
USER root

VOLUME /appz/log
VOLUME /appz/home
VOLUME /appz/cache
VOLUME /appz/data

EXPOSE 3000
ENV GF_PATHS_LOGS=/appz/log/
RUN mkdir /var/lib/grafana/dashboards 
ENV GF_PATHS_DATA=/appz/data
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get install -y ca-certificates && \
    apt-get install -y --reinstall ca-certificates

RUN apt-get update && apt-get install -y supervisor cron wget jq gnupg uuid-runtime python3 python3-pip logrotate libsystemd0 libgnutls30 openssl libssl3 libsasl2-2
ADD scripts/* /appz/scripts/
ADD supervisor/cron.conf /etc/supervisor/conf.d/cron.conf
ADD supervisor/grafana.conf  /etc/supervisor/conf.d/grafana.conf
RUN chown grafana. /appz/scripts/run.sh
ADD conf/logrotate.conf /etc/logrotate.d/logrotate.conf
RUN chmod 644 /etc/logrotate.d/logrotate.conf
RUN chmod u+x,o+x /appz/scripts/* 
RUN crontab -l | { cat; echo "*/15 * * * * /usr/bin/nice -5 /appz/scripts/cleanup.sh"; } | crontab - \
    && crontab -l | { cat; echo "0 4 * * * /bin/bash -c  /appz/scripts/logrotate.sh"; } | crontab - \
    && crontab -l | { cat;  echo "@reboot  /bin/bash -c  /appz/scripts/archive.sh"; } | crontab - 
#fluentd installation
ADD scripts/fluentd.sh /usr/local/bin/fluentd.sh
RUN chmod u+x /usr/local/bin/fluentd.sh
RUN /usr/local/bin/fluentd.sh
ADD conf/fluentd.conf /etc/td-agent/td-agent.conf
ADD plugin/out_graylog.rb /etc/td-agent/plugin/out_graylog.rb
RUN /usr/sbin/td-agent-gem install fluent-plugin-grok-parser
ADD supervisor/supervisord.conf /etc/supervisor/supervisord.conf
ADD supervisor/fluentd.conf /etc/supervisor/conf.d/fluentd.conf

ADD conf/grafana.ini /etc/grafana/
RUN chown -R grafana. /etc/grafana/
ADD dashboard/ /tmp/dashboards/
RUN grafana cli plugins install grafana-piechart-panel
ADD conf/datasource.yaml /etc/grafana/provisioning/datasources/
RUN chown -R grafana. /etc/grafana/provisioning/datasources
ADD conf/dash_providers.yaml /etc/grafana/provisioning/dashboards/
RUN chown -R grafana. /etc/grafana/provisioning/dashboards

ENTRYPOINT ["/usr/bin/supervisord", "-c", "/etc/supervisor/supervisord.conf", "-n"]
HEALTHCHECK --interval=1m --timeout=3s \
        CMD  bash -c "supervisorctl pid " || exit 1
