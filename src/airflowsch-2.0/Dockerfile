FROM appz/airflow:2.0

ADD supervisor/airflowsch.conf /etc/supervisor/conf.d/airflowsch.conf
ADD supervisor/log_retention.conf /etc/supervisor/conf.d/log_retention.conf

RUN crontab -l | ( cat; echo "0 0 * * * supervisorctl start log_retention"; ) | crontab -