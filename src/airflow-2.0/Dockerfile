FROM appz/ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ARG AIRFLOW_VERSION="2.11.0"
ARG AIRFLOW_DEPS="cncf.kubernetes,celery,snowflake,microsoft.azure,odbc,openlineage,sftp,smtp,microsoft.mssql"
ARG DBT_CORE_VERSION="1.8.8"
ARG DBT_POSTGRES_VERSION="1.8.2"
ARG DBT_SNOWFLAKE_VERSION="1.8.2"
ARG DBT_SQLSERVER_VERSION="1.8.4"
ARG COSMOS_VERSION="1.10.0"
ARG ELEMENTARY_VERSION="0.20.0"
ARG DBT_FABRIC_VERSION="1.8.7"

RUN apt-get update -y && \
    apt-get install -y software-properties-common && \
    add-apt-repository ppa:deadsnakes/ppa -y && \
    apt-get update -y && \
    apt-get install -y python3.12 python3.12-venv python3-pip netcat-openbsd tree libpq-dev ffmpeg && \
    apt-get install -y python3.12-dev gcc && \
    apt-get install -y freetds-dev libssl-dev && \
    apt-get install -y unixodbc-dev rsync libgssapi-krb5-2 libkrb5-dev maven openjdk-11-jdk

RUN curl https://packages.microsoft.com/keys/microsoft.asc | tee /etc/apt/trusted.gpg.d/microsoft.asc
RUN curl https://packages.microsoft.com/config/ubuntu/24.04/prod.list | tee /etc/apt/sources.list.d/mssql-release.list

RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 1 && \
    update-alternatives --config python3

RUN python3 -m venv /opt/venv && \
    . /opt/venv/bin/activate && \
    curl -sS https://bootstrap.pypa.io/get-pip.py | python && \
    python -m pip install --upgrade pip

ENV PATH="/opt/venv/bin:${PATH}"

RUN pip install --no-cache-dir supervisor setuptools==73.0.1 pytz
RUN pip install --no-cache-dir pandas Authlib statsd
RUN pip install --no-cache-dir psutil
RUN pip install --no-cache-dir pymssql pyodbc
COPY constraints.txt /appz/scripts
COPY scripts/requirements.txt /appz/scripts/requirements.txt
RUN rm -rf /usr/lib/python3/dist-packages/blinker* \
           /usr/lib/python3/dist-packages/Blinker* || true
RUN AIRFLOW_GPL_UNIDECODE=yes pip3 install apache-airflow[postgres${AIRFLOW_DEPS:+,}${AIRFLOW_DEPS}]==${AIRFLOW_VERSION} \
    --constraint "/appz/scripts/constraints.txt" && \
    pip install -r /appz/scripts/requirements.txt
RUN pip install --no-cache-dir celery[redis] astronomer-cosmos==${COSMOS_VERSION}

RUN python3 -m venv dbt_venv && . dbt_venv/bin/activate && \
    pip3 install --upgrade pip supervisor setuptools==73.0.1 && \
    pip3 install --no-cache-dir dbt-core==${DBT_CORE_VERSION} dbt-postgres==${DBT_POSTGRES_VERSION} dbt-snowflake==${DBT_SNOWFLAKE_VERSION} elementary-data==${ELEMENTARY_VERSION} && \
    deactivate

RUN python3 -m venv dbt_venv_1_4 && . dbt_venv_1_4/bin/activate && \
    pip install --upgrade pip supervisor setuptools==73.0.1 && \
    pip install --no-cache-dir pyodbc dbt-sqlserver==${DBT_SQLSERVER_VERSION} dbt-fabric==${DBT_FABRIC_VERSION} && deactivate

COPY conf/fluentd.conf /etc/td-agent/td-agent.conf
COPY scripts/ /appz/scripts/
RUN chmod +x /appz/scripts/*
ADD supervisor/ /etc/supervisor/conf.d/
RUN crontab -l | ( cat; echo "*/1 * * * * supervisorctl start rsync"; ) | crontab -

ADD scripts/plugins /appz/scripts/plugins
ENV AIRFLOW__CORE__PLUGINS_FOLDER=/appz/scripts/plugins
