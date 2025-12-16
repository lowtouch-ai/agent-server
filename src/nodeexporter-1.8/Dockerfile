FROM bitnamilegacy/node-exporter:1.8.2

USER root
EXPOSE 9100

RUN apt-get update -y && \
    apt-get install -y curl zip jq cron supervisor python3 python3-pip sudo python3.11-venv openssl linux-libc-dev libdb5.3 libldap-2.5-0 libldap-common libc6 dpkg build-essential libssl-dev libcurl4-gnutls-dev libexpat1-dev gettext unzip && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*
RUN curl -sL 'https://packages.treasuredata.com/GPG-KEY-td-agent' | gpg --dearmor -o /etc/apt/trusted.gpg.d/treasure-data.gpg && echo "deb http://deb.debian.org/debian sid main" >> /etc/apt/sources.list
RUN apt-get update
RUN apt-get install -y libvpx-dev  libaom-dev
# Install Go
RUN curl -LO https://golang.org/dl/go1.22.1.linux-amd64.tar.gz && \
    tar -C /usr/local -xzf go1.22.1.linux-amd64.tar.gz && \
    rm go1.22.1.linux-amd64.tar.gz

# Set up Python environment
RUN python3 -m venv /opt/venv && \
    /opt/venv/bin/pip install --upgrade pip && \
    /opt/venv/bin/pip install prometheus_client tailer

ENV DEBIAN_FRONTEND=noninteractive
VOLUME /appz/log
VOLUME /appz/home
VOLUME /appz/cache
VOLUME /appz/data
VOLUME /appz/backup
ENV HOME /appz/home
#fluentd installation
ADD scripts/fluentd.sh /usr/local/bin/fluentd.sh
RUN sh /usr/local/bin/fluentd.sh
ADD conf/fluentd.conf /etc/td-agent/td-agent.conf
ADD plugin/out_graylog.rb /etc/td-agent/plugin/out_graylog.rb
RUN /usr/sbin/td-agent-gem install fluent-plugin-grok-parser

ADD supervisor/supervisord.conf /etc/supervisor/supervisord.conf
ADD supervisor/* /etc/supervisor/conf.d/
ADD scripts /appz/scripts
RUN echo "15 8 * * * /usr/bin/nice -5 /appz/scripts/cleanup.sh" | crontab -

ENTRYPOINT ["/usr/bin/supervisord", "-c", "/etc/supervisor/supervisord.conf", "-n"]
HEALTHCHECK --interval=1m --timeout=3s \
        CMD  bash -c "supervisorctl pid " || exit 1
