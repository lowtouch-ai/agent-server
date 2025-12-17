FROM opensearchproject/opensearch:2.19.3

USER root
RUN yum update expat --releasever=2023.4.20240401 -y \
    && yum update -y \
    && yum install -y zip unzip tar cronie wget findutils logrotate procps jq curl --allowerasing

RUN yum -y install python3  \
        && wget https://bootstrap.pypa.io/pip/2.7/get-pip.py \
        &&  python3 get-pip.py \
        && pip3 install -U setuptools \
        && pip3 install supervisor boto3 requests

ADD supervisor/cron.conf /etc/supervisor/conf.d/
ADD supervisor/minio.conf /etc/supervisor/conf.d/
ADD supervisor/opensearch.conf /etc/supervisor/conf.d/
ADD scripts /appz/scripts
RUN wget -O /tmp/prometheus-exporter.zip https://github.com/opensearch-project/opensearch-prometheus-exporter/releases/download/2.19.3.0/prometheus-exporter-2.19.3.0.zip\    && yes | /usr/share/opensearch/bin/opensearch-plugin install repository-s3
RUN chmod +x /appz/scripts/*

#fluentd installation
ADD scripts/fluentd.sh /usr/local/bin/fluentd.sh
RUN bash /usr/local/bin/fluentd.sh
ADD conf/fluentd.conf /etc/fluent/fluent.conf
ADD plugin/out_graylog.rb /etc/fluent/plugin/out_graylog.rb
ADD scripts/fluentd_run.sh /appz/scripts/fluentd_run.sh
ADD supervisor/fluentd.conf /etc/supervisor/conf.d/fluentd.conf

ADD supervisor/tail.conf /etc/supervisor/conf.d/tail.conf
ADD supervisor/supervisord.conf /etc/supervisor/supervisord.conf
ADD conf/logrotate.conf /etc/logrotate.d/logrotate.conf
RUN chmod 644 /etc/logrotate.d/logrotate.conf
ENV plugins.security.disabled=true
EXPOSE 9200 9300
VOLUME /appz/log
VOLUME /appz/home
VOLUME /appz/cache
VOLUME /appz/backup

RUN (crontab -l 2>/dev/null; echo "0 4 * * * /bin/bash -c /appz/scripts/logrotate.sh") | crontab - \
    && (crontab -l 2>/dev/null; echo "@reboot /bin/bash -c /appz/scripts/archive.sh") | crontab - \
    && (crontab -l 2>/dev/null; echo "0 3 * * * /bin/bash -c /appz/scripts/cleanup.sh") | crontab - \
    && (crontab -l 2>/dev/null; echo "*/50 * * * * /usr/local/bin/supervisorctl start minio_backup") | crontab -

RUN echo 'alias ctl="supervisorctl"' >> /appz/.bashrc \ 
	&& echo 'alias status="supervisorctl status"' >> /appz/.bashrc \ 
	&& echo 'alias start="supervisorctl start"' >> /appz/.bashrc \
	&& echo 'alias stop="supervisorctl stop"' >> /appz/.bashrc \
	&& echo 'alias restart="supervisorctl restart"' >> /appz/.bashrc \
	&& echo 'alias scripts="cd /appz/scripts"' >> /appz/.bashrc \
	&& echo 'alias log="cd /appz/log"' >> /appz/.bashrc \ 
	&& echo 'alias cache="cd /appz/cache"' >> /appz/.bashrc \ 
	&& echo 'alias data="cd /appz/data"' >> /appz/.bashrc 
ENTRYPOINT ["/usr/local/bin/supervisord", "-c", "/etc/supervisor/supervisord.conf", "-n"]
HEALTHCHECK --interval=1m --timeout=3s \
       CMD  bash -c "supervisorctl pid " || exit 1
