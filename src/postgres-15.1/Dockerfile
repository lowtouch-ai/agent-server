FROM appz/ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install jq sudo wget -y
RUN set -ex; \
        if ! command -v gpg > /dev/null; then \
                apt-get update; \
                apt-get install -y --no-install-recommends \
                        gnupg \
                        dirmngr \
                ; \
                rm -rf /var/lib/apt/lists/*; \
        fi

RUN set -eux; \
        groupadd -r postgres --gid=999; \
        useradd -r -g postgres --uid=999 --home-dir=/appz/home/postgresql --shell=/bin/bash postgres

ENV GOSU_VERSION 1.11
RUN set -x \
        && apt-get install -y \
        cron --no-install-recommends ca-certificates \
        gnupg2 gcc zip unzip logrotate \
        jq --no-install-recommends libnss-wrapper uuid-runtime \
        python3-pip python3-dev libpq-dev python3-psycopg2
RUN  wget -O /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$(dpkg --print-architecture)" \
        && wget -O /usr/local/bin/gosu.asc "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$(dpkg --print-architecture).asc" \
        && export GNUPGHOME="$(mktemp -d)" \
        && gpg --batch --keyserver hkps://keys.openpgp.org --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4 \
        && gpg --batch --verify /usr/local/bin/gosu.asc /usr/local/bin/gosu \
        && { command -v gpgconf > /dev/null && gpgconf --kill all || :; } \
        && rm -rf "$GNUPGHOME" /usr/local/bin/gosu.asc \
        && chmod +x /usr/local/bin/gosu \
        && gosu nobody true \
RUN  cd /usr/local/bin \
  && ln -s /usr/bin/python3 python \
  && pip3 install --upgrade pip \
  && pip install supervisor \
  && pip3 install pyaml \
  && pip3 install wget \
  && pip3 install python-dateutil \
  && pip3 install pytz \
  && pip3 install psycopg2 \
  && pip3 install requests
RUN set -eux; \
        if [ -f /etc/dpkg/dpkg.cfg.d/docker ]; then \
                grep -q '/usr/share/locale' /etc/dpkg/dpkg.cfg.d/docker; \
                sed -ri '/\/usr\/share\/locale/d' /etc/dpkg/dpkg.cfg.d/docker; \
                ! grep -q '/usr/share/locale' /etc/dpkg/dpkg.cfg.d/docker; \
        fi; \
        apt-get install -y locales; rm -rf /var/lib/apt/lists/*; \
        localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8
ENV LANG en_US.utf8

RUN set -eux; \
        rm -rf /var/lib/apt/lists/*

RUN mkdir /docker-entrypoint-initdb.d

RUN key='B97B0AFCAA1A47F044F244A07FCC7D46ACCC4CF8'; \
    found=''; \
    for server in \
          ha.pool.sks-keyservers.net \
          hkp://p80.pool.sks-keyservers.net:80 \
          keyserver.ubuntu.com \
          hkp://keyserver.ubuntu.com:80 \
    ; do \
        echo "Fetching GPG key from $server"; \
        gpg --keyserver "$server" --recv-keys "$key" && found=yes && break; \
    done; \
    test -z "$found" && echo >&1 "error: Failed to fetch GPG key $key" && exit 1; \
RUN set -ex; \
        gpg --batch --export "$key" > /etc/apt/trusted.gpg.d/postgres.gpg; \
        command -v gpgconf > /dev/null && gpgconf --kill all; \
        rm -rf "$GNUPGHOME"; \
        apt-key list

ENV PG_MAJOR 15
ENV PG_VERSION 15.1-1.pgdg18.04+1
RUN apt-get update \
    && DEBIAN_FRONTEND="noninteractive" apt-get -y install tzdata
RUN set -ex; \
        \
        export PYTHONDONTWRITEBYTECODE=1; \
        \
        dpkgArch="$(dpkg --print-architecture)"; \
        case "$dpkgArch" in \
                amd64|i386|ppc64el|arm64) \
                        echo "deb http://apt.postgresql.org/pub/repos/apt jammy-pgdg main" > /etc/apt/sources.list.d/pgdg.list; \
                        ;; \
                *) \
                        echo "deb-src https://apt-archive.postgresql.org/pub/repos/apt bionic-pgdg main" > /etc/apt/sources.list.d/pgdg.list; \
                        \
                        tempDir="$(mktemp -d)"; \
                        cd "$tempDir"; \
                        \
                        savedAptMark="$(apt-mark showmanual)"; \
                        \
                        apt-get build-dep -y \
                                postgresql-common pgdg-keyring \
                                "postgresql-$PG_MAJOR=$PG_VERSION" \
                        ; \
                        DEB_BUILD_OPTIONS="nocheck parallel=$(nproc)" \
                                apt-get source --compile \
                                        postgresql-common pgdg-keyring \
                                        "postgresql-$PG_MAJOR=$PG_VERSION" \
                        ; \
                        \
                        apt-mark showmanual | xargs apt-mark auto > /dev/null; \
                        apt-mark manual $savedAptMark; \
                        \
                        ls -lAFh; \
                        dpkg-scanpackages . > Packages; \
                        grep '^Package: ' Packages; \
                        echo "deb [ trusted=yes ] file://$tempDir ./" > /etc/apt/sources.list.d/temp.list; \
                        apt-get -o Acquire::GzipIndexes=false update; \
                        ;; \
        esac; \
        \
        apt update && apt-get install -y postgresql-$PG_MAJOR postgresql-client-$PG_MAJOR; \
        sed -ri 's/#(create_main_cluster) .*$/\1 = false/' /etc/postgresql-common/createcluster.conf; \
        rm -rf /var/lib/apt/lists/*; \
        \
        if [ -n "$tempDir" ]; then \
                apt-get purge -y --auto-remove; \
                rm -rf "$tempDir" /etc/apt/sources.list.d/temp.list; \
        fi; \
        \
        find /usr -name '*.pyc' -type f -exec bash -c 'for pyc; do dpkg -S "$pyc" &> /dev/null || rm -vf "$pyc"; done' -- '{}' +
RUN set -eux; \
        dpkg-divert --add --rename --divert "/usr/share/postgresql/postgresql.conf.sample.dpkg" "/usr/share/postgresql/$PG_MAJOR/postgresql.conf.sample"; \
        cp -v /usr/share/postgresql/postgresql.conf.sample.dpkg /usr/share/postgresql/postgresql.conf.sample; \
        ln -sv ../postgresql.conf.sample "/usr/share/postgresql/$PG_MAJOR/"; \
        sed -ri "s!^#?(listen_addresses)\s*=\s*\S+.*!\1 = '*'!" /usr/share/postgresql/postgresql.conf.sample; \
        grep -F "listen_addresses = '*'" /usr/share/postgresql/postgresql.conf.sample
RUN mkdir -p /var/run/postgresql && chown -R postgres:postgres /var/run/postgresql && chmod 2777 /var/run/postgresql

ADD scripts/activate_postgres.py /appz/scripts/
ADD scripts/backup.sh /appz/scripts/
ADD scripts/psql_start.sh /appz/scripts/
ENV PATH $PATH:/usr/lib/postgresql/$PG_MAJOR/bin
ENV PGDATA /appz/data
ADD scripts/docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /appz/scripts/psql_start.sh
RUN ln -s usr/local/bin/docker-entrypoint.sh /
RUN chmod +rx /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /appz/scripts/activate_postgres.py
RUN chmod +x /appz/scripts/backup.sh
VOLUME /appz/backup
VOLUME /appz/log
#VOLUME /dev/shm

EXPOSE 5432
RUN crontab -l | { cat; echo "@reboot chown -R postgres:postgres $PGDATA"; } | crontab - \
    && crontab -l | { cat; echo "@reboot find /usr/lib/python2.7 -name "*.pyc" -exec rm -f {} \;"; } | crontab - \
    && crontab -l | { cat; echo "@reboot mkdir -p /appz/home/postgresql"; } | crontab - \
    && crontab -l | { cat; echo "@reboot chown -R postgres:postgres /appz/home/postgresql"; } | crontab - \
    && crontab -l | { cat; echo "0 23 * * * /bin/bash   /appz/scripts/backup.sh"; } | crontab - \
    && crontab -l | { cat; echo "@reboot chmod 777 $PGDATA "; } | crontab -
ADD supervisor/  /etc/supervisor/conf.d/
HEALTHCHECK --interval=1m --timeout=3s \
        CMD  bash -c "supervisorctl pid " || exit 1
