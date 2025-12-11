FROM wordpress:6.7.0-php8.3-apache
RUN apt-get update && apt-get install  wget cron gnupg2 gcc zip unzip uuid-runtime jq logrotate bc rsync lsyncd cpulimit -y
RUN apt-get update \
  && apt-get install -y python3-pip python3-dev at python3-venv \
  && cd /usr/local/bin \
  && ln -s /usr/bin/python3 python
RUN python3 -m venv /venv
ENV PATH="/venv/bin:$PATH"
RUN pip3 install --upgrade pip \
    && pip install supervisor \
    && pip3 install pyaml \
    && pip3 install wget \
    && pip3 install python-dateutil \
    && pip3 install mysql-connector-python \
    && pip3 install pytz \
    && pip3 install xlrd \
    && pip3 install openpyxl \
    && pip3 install pandas Flask qrcode[pil]
RUN a2enmod ssl &&\
      a2enmod proxy_http &&\
      a2enmod headers

WORKDIR /root
RUN mkdir /downloads

#Fluentd installation
ADD scripts/fluentd.sh /usr/local/bin/fluentd.sh
RUN bash /usr/local/bin/fluentd.sh
ADD conf/fluentd.conf /etc/fluent/fluent.conf
ADD supervisor/fluentd.conf /etc/supervisor/conf.d/fluentd.conf 
ADD scripts/fluentd_run.sh /appz/scripts/fluentd_run.sh
   
WORKDIR /var/www/html
ENV WP_INSTALL_DIR=/var/www/html/
ENV APACHE_LOG_DIR=/appz/log/
ENV WP_CLI_CONFIG_PATH=/appz/home/.wp-cli/config.yml
ENV CERT_KEY_PATH=/etc/ssl/certs/GSWildcard_pk.pem
ENV CERT_PATH=/etc/ssl/certs/GSWildcard_cert.pem
ENV MOUNT_POINT=/var/www/html/wp-content/uploads
RUN wget https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    && chmod +x wp-cli.phar \
    && mv wp-cli.phar /usr/local/bin/wp

ADD supervisor/* /etc/supervisor/conf.d/
ADD conf/supervisord.conf /etc/supervisor/
ADD scripts/wp-init.sh /
RUN chmod +x /wp-init.sh
ADD scripts/cpulimit.sh /appz/scripts/
RUN chmod +x /appz/scripts/cpulimit.sh
ADD scripts/cron.sh /appz/scripts/
ADD scripts/cleanup.sh /appz/scripts/
ADD scripts/backup.sh /appz/scripts/
ADD scripts/logrotate.sh /appz/scripts/
ADD scripts/restore-files.sh /appz/scripts/
ADD scripts/archive.sh /appz/scripts/
ADD scripts/get_health.sh /appz/scripts/ 
ADD conf/logrotate.conf /etc/logrotate.d/logrotate.conf
ADD scripts/set_permission.sh /appz/scripts/
ADD scripts/website_cleanup.py /appz/scripts/
ADD scripts/init_cleanup.sh /appz/scripts/
RUN chmod 644 /etc/logrotate.d/logrotate.conf
VOLUME /appz/log
VOLUME /appz/home
VOLUME /appz/cache
VOLUME /appz/data
VOLUME /appz/backup
RUN crontab -l | { cat; echo "*/15 * * * * /usr/bin/nice -5 /appz/scripts/cleanup.sh"; } | crontab - \
    && crontab -l | { cat; echo "0 23 * * * /usr/bin/nice -5 /appz/scripts/backup.sh"; } | crontab - \
    && crontab -l | { cat; echo "0 4 * * * /bin/bash -c  /appz/scripts/logrotate.sh"; } | crontab - \
    && crontab -l | { cat;  echo "@reboot  /bin/bash -c  /appz/scripts/archive.sh"; } | crontab - \
    && crontab -l | { cat; echo "*/15 * * * * /bin/bash  /appz/scripts/get_health.sh"; } | crontab -  

RUN mv /usr/local/etc/php/php.ini-production /usr/local/etc/php/php.ini \
    && sed -i 's/upload_max_filesize = 2M/upload_max_filesize = 150M/g' /usr/local/etc/php/php.ini \
    && sed -i 's/post_max_size = 8M/post_max_size = 150M/g' /usr/local/etc/php/php.ini \
    && sed -i 's/memory_limit = 128M/memory_limit = 256M/g' /usr/local/etc/php/php.ini \ 
    && sed -i 's/max_input_time = 60/max_input_time = 300/g' /usr/local/etc/php/php.ini \
    && sed -i 's/max_execution_time = 30/max_execution_time = 300/g' /usr/local/etc/php/php.ini

ADD scripts/wp-config.php /var/www/html/
RUN chown www-data:www-data /var/www/html/wp-config.php
RUN chmod -R o+r /var/www/html/*
RUN sed -i '/session    required     pam_loginuid.so/c\#session    required   pam_loginuid.so' /etc/pam.d/cron

#ADD conf/demo.conf /etc/apache2/sites-enabled/demo.conf

#
# ***** IF YOU DONT HAVE THE .pem FILES, SEE certs/readme.txt *****
##
#ADD certs/GSWildcard_cert.pem /etc/ssl/certs/GSWildcard_cert.pem
#ADD certs/GSWildcard_pk.pem /etc/ssl/certs/GSWildcard_pk.pem

ADD scripts/vault_httpd.sh /usr/local/bin/vault_httpd.sh
RUN chmod +x /usr/local/bin/vault_httpd.sh 
ADD wp-contents /wp-contents
ADD scripts/download.py /appz/scripts/download.py
ADD scripts/activate.py /appz/scripts/activate.py
ADD scripts/options_import.py /appz/scripts/options_import.py
RUN python3 /appz/scripts/download.py
#WORDPRESS_HA
ENV DEST_FOLDER=/var/www/html/wp-content/uploads/
RUN apt-get update && apt-get install default-mysql-client haproxy -y  
RUN mv /etc/haproxy/haproxy.cfg  /etc/haproxy/haproxy.cfg.original \
    && sed -i "s/ENABLED=0/ENABLED=1/g" /etc/default/haproxy 
ADD conf/haproxy.cfg /etc/haproxy/
RUN chmod o+r /etc/haproxy/haproxy.cfg
RUN sed -i -e s@/var/log/haproxy.log@$r/appz/log/haproxy-traffic.log@ /etc/rsyslog.d/49-haproxy.conf
####FILESYNC########
ENV FILESYNC_ENABLE=yes
ENV ATTACHMENTS_STORAGE_PATH=/var/www/html/wp-content/uploads
COPY conf/rsyncd.* /etc/
RUN chmod 600 /etc/rsyncd.* && mkdir /etc/lsyncd 
RUN mkdir -p /appz/log && touch /appz/log/lsyncd.{log,status}
ADD scripts/lsyncd_watch.sh /appz/scripts/
ADD supervisor/rsync.conf /etc/supervisor/conf.d
ADD scripts/rsync.sh /appz/scripts/
ADD scripts/lsyncd.sh /appz/scripts/
ADD scripts/prepare.sh /appz/scripts/
RUN chmod +x /appz/scripts/*
RUN crontab -l | { cat;  echo "*/3 * * * * /bin/bash -c  /appz/scripts/lsyncd_watch.sh"; } | crontab -
EXPOSE 12000
# REVISION 2
ENTRYPOINT ["supervisord", "-c", "/etc/supervisor/supervisord.conf", "-n"]

HEALTHCHECK --interval=1m --timeout=3s \
        CMD  bash -c "supervisorctl pid " || exit 1
