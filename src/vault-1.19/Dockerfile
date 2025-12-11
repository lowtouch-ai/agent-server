FROM appz/ubuntu:22.04
ENV VAULT_VERSION="1.19.5"
ENV VAULT_SKIP_VERIFY=true
ENV VAULT_ADDR="https://localhost:8200"

RUN apt-get update && apt-get install -y sudo apache2 apache2-utils curl perl openssh-client supervisor ncurses-bin ssl-cert libexpat1 libcap2 libapache2-mod-wsgi-py3 \
    && apt-get install -y python3 \
    && apt-get install -y python3-distutils python3-venv python3-pip \
    && apt-get autoremove -y && apt-get clean && rm -rf /var/lib/apt/lists/*
RUN groupadd vault && \
    useradd -r -g  vault vault
RUN adduser www-data sudo
RUN echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
RUN apt-get update && apt-get install -y gnupg wget && \
    VAULT_GPGKEY_PRIMARY=91A6E7F85D05C65630BEF18951852D87348FFC4C; \
    VAULT_GPGKEY_FALLBACK=798AEC654E5C15428C8E42EEAA16FCBCA621E701; \
    export GNUPGHOME=$(mktemp -d); \
    found=''; \
    for server in \
        hkps://keyserver.ubuntu.com \
        hkps://pgp.mit.edu \
        hkps://keys.openpgp.org \
    ; do \
        echo "Fetching GPG key $VAULT_GPGKEY_PRIMARY from $server"; \
        gpg --keyserver "$server" --recv-keys "$VAULT_GPGKEY_PRIMARY" && found=yes && break; \
    done; \
    if [ -z "$found" ]; then \
        echo "Primary GPG key $VAULT_GPGKEY_PRIMARY not found, trying fallback key $VAULT_GPGKEY_FALLBACK"; \
        found=''; \
        for server in \
            hkps://keyserver.ubuntu.com \
            hkps://pgp.mit.edu \
            hkps://keys.openpgp.org \
        ; do \
            echo "Fetching GPG key $VAULT_GPGKEY_FALLBACK from $server"; \
            gpg --keyserver "$server" --recv-keys "$VAULT_GPGKEY_FALLBACK" && found=yes && break; \
        done; \
        test -z "$found" && echo >&2 "error: failed to fetch both GPG keys" && exit 1; \
    fi; \
    mkdir -p /tmp/build && \
    cd /tmp/build && \
    wget https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip && \
    wget https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_SHA256SUMS && \
    wget https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_SHA256SUMS.sig && \
    grep vault_${VAULT_VERSION}_linux_amd64.zip vault_${VAULT_VERSION}_SHA256SUMS | sha256sum -c && \
    unzip -d /bin vault_${VAULT_VERSION}_linux_amd64.zip && \
    cd /tmp && \
    rm -rf /tmp/build
RUN mkdir -p /vault/logs && \
    mkdir -p /vault/config && \
    mkdir -p /vault/certs && \
    chown -R vault:vault /vault
COPY conf/local.json /vault/config/local.json
#...............apache config..................
COPY certs/vault-selfsigned.key /vault/keys/vault-selfsigned.key
ADD scripts/list_secret.sh /appz/scripts/list_secret.sh
ADD scripts/client/ /appz/scripts/client/
ADD scripts/ /appz/scripts/
RUN chown www-data:www-data /appz/scripts/client/*
RUN chmod 775 /appz/scripts/list_secret.sh
COPY certs/vault-selfsigned.crt /vault/keys/vault-selfsigned.crt
ADD conf/appz_policy.hcl /appz/scripts/appz_policy.hcl
ADD conf/app_policy.hcl /appz/scripts/app_policy.hcl
ADD scripts/set_secret.sh /appz/scripts/set_secret.sh
ADD scripts/get_approle.sh /appz/scripts/get_approle.sh
RUN chmod 775 /appz/scripts/get_approle.sh
ADD scripts/vault_init.sh /appz/scripts/vault_init.sh
RUN chmod 775 /appz/scripts/set_secret.sh
RUN chmod 775 /appz/scripts/vault_init.sh
RUN chmod +x /appz/scripts/copy_secret.sh
ADD conf/vault.conf /etc/apache2/sites-available/
RUN a2dissite 000-default
RUN a2ensite vault.conf
ADD supervisor/httpd.conf /etc/supervisor/conf.d
VOLUME /vault/keys
VOLUME /vault/config
EXPOSE 8200
EXPOSE 80
ENV APACHE_LOG_DIR=/appz/log/
COPY scripts/entrypoint.sh /usr/local/bin/vault.sh
RUN chmod 775 /usr/local/bin/vault.sh
ADD supervisor/vault.conf /etc/supervisor/conf.d/vault.conf
ADD supervisor/vault_init.conf /etc/supervisor/conf.d/vault_init.conf
RUN python3 -m pip install --upgrade pip \
    && python3 -m pip install setuptools random-password-generator
ADD scripts/wsgi_app.py /appz/scripts/wsgi_app.py
RUN chmod 775 /appz/scripts/wsgi_app.py
ADD conf/mod-wsgi.conf /etc/apache2/conf-available/mod-wsgi.conf
RUN a2enconf mod-wsgi
RUN crontab -l | { cat; echo "@reboot  chown www-data:www-data  /appz/log "; } | crontab - \
    && crontab -l | { cat; echo "@reboot  chmod 775 /appz/log "; } | crontab -

