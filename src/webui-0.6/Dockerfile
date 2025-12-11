FROM appz/python:3.11 AS builder

ENV DEBIAN_FRONTEND=noninteractive
ARG OPENWEBUI_VERSION
ARG APPZ_ENV
RUN apt-get update && apt-get install -y \
    git \
    vim \
    curl \
    build-essential \
    autoconf \
    automake \
    libtool \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*


RUN git clone --depth 1 --single-branch --branch $OPENWEBUI_VERSION https://github.com/lowtouch-ai/open-webui.git /app
WORKDIR /app/backend
RUN python -m venv /app/backend/venv && \
    /app/backend/venv/bin/pip install --upgrade pip && \
    /app/backend/venv/bin/pip install -r /app/backend/requirements.txt

WORKDIR /app

RUN sed -i 's/\(WEBUI_NAME = os\.environ\.get("WEBUI_NAME", \)"Open WebUI"/\1"lowtouch.ai"/' backend/open_webui/env.py && \
    sed -i 's/ (Open WebUI)//g' backend/open_webui/env.py && \
    sed -i 's/WebUI/lowtouch.ai/g' src/lib/components/layout/Overlay/AccountPending.svelte && \
    find . -type f -exec sed -i 's/Open WebUI/lowtouch.ai/g' {} +

COPY assets/favicon.png /app/static/static/favicon.png
COPY assets/splash.png /app/static/static/splash.png
COPY assets/splash.png /app/static/static/splash-dark.png
COPY assets/* /app/static/favicon/
COPY assets/favicon.png /app/static/favicon.png

RUN npm ci --force && \
    npm run build && \
    npm cache clean --force && \
    rm -rf node_modules .git

ADD scripts /appz/scripts

# Final stage
FROM appz/python:3.11

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    curl \
    moreutils \
    libgl1-mesa-glx \
    libglib2.0-0 \
    fonts-noto-color-emoji \
    fonts-symbola \
    ffmpeg \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /app /app
COPY --from=builder /appz /appz

COPY supervisor/* /etc/supervisor/conf.d/

