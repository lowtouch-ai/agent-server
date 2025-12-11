FROM mariadb:lts-jammy

RUN apt-get update && apt-get install supervisor wget unzip cron curl jq gcc make logrotate bc net-tools  -y 
RUN apt-get update && apt-get install -y python3-mysqldb python3-pip python3-dev libmysqlclient-dev uuid-runtime -y

RUN apt-get update -y
RUN apt-get install -y util-linux -f -o APT::Immediate-Configure=0
RUN apt-get install libc6 -y
RUN apt-get install --only-upgrade -y libdb5.3 libnghttp2-14 rsync perl-base libpolkit-agent-1-0 libpolkit-gobject-1-0 policykit-1 libxml2 tar libreadline8 libkrb5support0 libgssapi-krb5-2 krb5-locales tar libk5crypto3 libkrb5-3 gawk libpcre3 libsasl2-2 libsasl2-modules-db ncurses-bin ncurses-base libtinfo6 libncurses6 libncursesw6 libonig5 libdbi-perl openssl
RUN apt-get install -f -y
RUN apt-get autoremove -y

RUN pip3 install python-dateutil \
  && pip3 install requests \
  && pip3 install subprocess.run \
  && pip3 install pyaml \
  && pip3 install wget \
  && pip3 install mysqlclient \
  && pip3 install mysql-connector-python \
  && pip3 install PyMySQL

### Add mysqlexporter
ADD https://github.com/prometheus/mysqld_exporter/releases/download/v0.13.0/mysqld_exporter-0.13.0.linux-amd64.tar.gz /tmp/
WORKDIR /tmp/
RUN tar -xvzf mysqld_exporter-0.13.0.linux-amd64.tar.gz
RUN mv mysqld_exporter-0.13.0.linux-amd64/mysqld_exporter /usr/local/bin/



#fluentd installation
ADD scripts/fluentd.sh /usr/local/bin/fluentd.sh
RUN sh /usr/local/bin/fluentd.sh
ADD conf/fluentd.conf /etc/td-agent/td-agent.conf
ADD plugin/out_graylog.rb /etc/td-agent/plugin/out_graylog.rb
RUN /usr/sbin/td-agent-gem install fluent-plugin-grok-parser
RUN apt-get autoremove -y binutils
ADD scripts/ /appz/scripts/
RUN chmod +x /appz/scripts/*.sh
ADD scripts/mysql_vault.sh /usr/local/bin/mysql_vault.sh
ADD scripts/exporter.sh  /appz/scripts/exporter.sh
RUN chmod +x /usr/local/bin/mysql_vault.sh
ADD supervisor/ /etc/supervisor/conf.d/
ADD conf/supervisord.conf /etc/supervisor/
ADD supervisor/mariadbexporter.conf /etc/supervisor/conf.d/mariadbexporter.conf
ADD conf/logrotate.conf /etc/logrotate.d/logrotate.conf
RUN chmod 644 /etc/logrotate.d/logrotate.conf
VOLUME /appz/log
VOLUME /appz/home
VOLUME /appz/cache
VOLUME /appz/data
VOLUME /appz/backup
ADD conf/my.cnf /etc/mysql/
RUN echo "*/15 * * * * /usr/bin/nice -5 bash /appz/scripts/cleanup.sh" | crontab - \
    && crontab -l | { cat; echo "0 23 * * * /bin/bash   /appz/scripts/backup.sh"; } | crontab - \
    && crontab -l | { cat; echo "0 4 * * * /bin/bash   /appz/scripts/logrotate.sh"; } | crontab - \
    && crontab -l | { cat;  echo "@reboot  /bin/bash  /appz/scripts/archive.sh"; } | crontab - \
    && crontab -l | { cat; echo "*/15 * * * * /bin/bash  /appz/scripts/get_health.sh"; } | crontab - 
ENV MOUNT_POINT=/appz/data
EXPOSE 9104
ENTRYPOINT ["/usr/bin/supervisord", "-n"]
HEALTHCHECK --interval=1m --timeout=3s \
        CMD  bash -c "supervisorctl pid " || exit 1
