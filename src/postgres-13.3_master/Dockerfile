FROM appz/postgres:13.3

ENV DEBIAN_FRONTEND=noninteractive

RUN dpkgArch="$(dpkg --print-architecture)"; \
    if [ "$dpkgArch" = "arm64" ]; then \
        sed -i 's|http://archive.ubuntu.com/ubuntu|http://ports.ubuntu.com/ubuntu-ports|g' /etc/apt/sources.list; \
        apt-get update && apt-get install -y openssh-client supervisor libc6 libc-bin locales; \
    else \
        apt-get update && apt-get install -y openssh-client supervisor libc6 libc-bin locales; \
        apt-get install --only-upgrade -y libpython2.7-stdlib python2.7; \
    fi

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen \
    && locale-gen en_US.UTF-8 \
    && update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 LANGUAGE=en_US.UTF-8 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
RUN apt-get update && apt-get install -y golang git && \
    rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8
ENV LANGUAGE=en_US.UTF-8

ADD scripts/postgres-contents /appz/scripts/postgres-contents
COPY webapps/ /tmp/
RUN for file in /tmp/*.zip; \
do \
    zip_name="$(basename -- "$file")" \
    && echo "zip name is "$zip_name"" \
    && file_name="${zip_name%.*}" \
    && echo "sub-folder  name is "$file_name"" \
    && if [ -f "$file" ]; then \
        dest_folder="$(uuidgen)" \
        && echo "Creating Destination folder:  "$dest_folder"" \
        && mkdir -v /tmp/"$dest_folder" \
        && unzip /tmp/"$file_name".zip -d /tmp/"$dest_folder" \
        && chmod -Rv a+x /tmp/"$dest_folder/$file_name" \
        && cp -rv /tmp/$dest_folder/$file_name/* /appz/scripts/postgres-contents \
        && rm -rfv /tmp/$dest_folder \
        && rm -rfv /tmp/"$zip_name"; \
    else \
        echo "zip file not found"; \
    fi; \
done

RUN set -eux; \
    dpkgArch="$(dpkg --print-architecture)"; \
    case "$dpkgArch" in \
        amd64) \
            wget https://github.com/prometheus-community/postgres_exporter/releases/download/v0.17.0/postgres_exporter-0.17.0.linux-amd64.tar.gz -O /tmp/postgres_exporter.tar.gz; \
            ;; \
        arm64) \
            wget https://github.com/prometheus-community/postgres_exporter/releases/download/v0.17.0/postgres_exporter-0.17.0.linux-arm64.tar.gz -O /tmp/postgres_exporter.tar.gz; \
            ;; \
        *) \
            echo "Unsupported architecture: $dpkgArch"; \
            exit 1; \
            ;; \
    esac

WORKDIR /tmp/
RUN tar -xvzf /tmp/postgres_exporter.tar.gz && \
    mv postgres_exporter-0.17.0.linux-*/postgres_exporter /usr/local/bin/ && \
    rm -rf /tmp/postgres_exporter*

ADD scripts/postgres_master.sh /appz/scripts/postgres_master.sh
ADD scripts/psqlexporter.sh /appz/scripts/
ADD scripts/psqlexporter.sh /appz/scripts/
ADD scripts/start.sh /appz/scripts/
RUN chmod +x /appz/scripts/start.sh
RUN chmod +x /appz/scripts/psqlexporter.sh
RUN chmod 0770 /appz/scripts/postgres_master.sh
ADD supervisor/ /etc/supervisor/conf.d/
