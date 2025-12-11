FROM appz/ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update -y && \
    apt-get install -y software-properties-common && \
    add-apt-repository ppa:deadsnakes/ppa -y && \    
    apt-get install -y python3.9 python3.9-distutils python3.9-venv python3-pip netcat tree rsync

RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.9 1 && \
    update-alternatives --config python3

RUN pip3 install --upgrade pip supervisor setuptools==62.4.0
RUN pip3 install --upgrade GitPython PyYAML

ADD scripts/ /appz/scripts/
RUN chmod +x /appz/scripts/*

COPY conf/rsyncd.* /etc/
ADD supervisor/rsync.conf /etc/supervisor/conf.d

ADD supervisor/git_runner.conf /etc/supervisor/conf.d/git_runner.conf
