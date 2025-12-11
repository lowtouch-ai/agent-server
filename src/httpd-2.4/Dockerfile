FROM appz/ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive \
    APACHE_LOG_DIR=/var/log/apache2 \
    APACHE_PID_FILE=/var/run/apache2/apache2.pid \
    APACHE_RUN_DIR=/var/run/apache2 \
    APACHE_RUN_USER=www-data \
    APACHE_RUN_GROUP=www-data

RUN apt-get update -y && \
    apt-get install -y apache2 certbot python3-certbot-apache openssl wget libxml2-dev libapache2-mod-auth-openidc vim && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
RUN mkdir -p ${APACHE_RUN_DIR} && \
    chown -R ${APACHE_RUN_USER}:${APACHE_RUN_GROUP} ${APACHE_RUN_DIR}

RUN rm -rf ${APACHE_LOG_DIR} && ln -s /appz/log ${APACHE_LOG_DIR}
ADD scripts /appz/scripts
RUN chmod +x /appz/scripts/*.sh
# Enable necessary Apache modules
RUN a2enmod ssl proxy proxy_http rewrite headers
# Copy SSL certificates into the container
#COPY certs /etc/letsencrypt
# Set permissions and ownership for certificates
RUN chmod -R 600 /etc/letsencrypt/* && \
    chown -R root:root /etc/letsencrypt/*
COPY conf/api.htpasswd /etc/apache2/api.htpasswd
RUN chmod 640 /etc/apache2/api.htpasswd
RUN chown root:www-data /etc/apache2/api.htpasswd

RUN a2dissite 000-default.conf

ADD supervisor/httpd.conf /etc/supervisor/conf.d/httpd.conf
RUN pip3 install prometheus-client

# Download and install apache_exporter based on architecture
RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "x86_64" ]; then \
        wget -P /tmp https://github.com/Lusitaniae/apache_exporter/releases/download/v0.11.0/apache_exporter-0.11.0.linux-amd64.tar.gz; \
    elif [ "$ARCH" = "aarch64" ]; then \
        wget -P /tmp https://github.com/Lusitaniae/apache_exporter/releases/download/v0.11.0/apache_exporter-0.11.0.linux-arm64.tar.gz; \
    else \
        echo "Unsupported architecture: $ARCH"; \
        exit 1; \
    fi && \
    tar -xzvf /tmp/apache_exporter-0.11.0.*.tar.gz && \
    cp -ivr apache_exporter-0.11.0.*/apache_exporter /usr/local/bin && \
    chmod +x /usr/local/bin/apache_exporter
ADD conf/* /etc/apache2/sites-enabled/
# Add scripts and configuration for exporter
ADD scripts/exporter.sh /appz/scripts/exporter.sh
ADD supervisor/httpd_exporter.conf /etc/supervisor/conf.d/httpd_exporter.conf
ADD scripts/custom_exporter.py /appz/scripts/custom_exporter.py
ADD supervisor/custom_exporter.conf /etc/supervisor/conf.d/custom_exporter.conf

EXPOSE 80 443
