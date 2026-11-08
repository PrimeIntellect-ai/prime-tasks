#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        imagemagick \
        fonts-dejavu-core \
        g++ \
        make \
        cmake \
        libmicrohttpd-dev \
        libboost-all-dev \
        tar \
        curl \
        wget

    pip3 install pytest

    mkdir -p /app
    cd /app

    # 1. Create the documentation archive
    mkdir -p /app/docs_raw
    echo "Welcome to the v1.0 documentation. This v1.0 system is deprecated." > /app/docs_raw/intro.txt
    echo "API v1.0 reference guide." > /app/docs_raw/api.txt
    tar -czf /app/docs.tar.gz -C /app/docs_raw .
    rm -rf /app/docs_raw

    # 2. Create the image fixture
    convert -size 400x100 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 10,50 'SYSTEM_ARCHITECTURE_SECRET_8842'" /app/diagram.png

    # 3. Create the route configuration
    cat << 'EOF' > /app/route_config.txt
/intro=/app/docs/intro.txt
/api=/app/docs/api.txt
/architecture=/app/docs/diagram.txt
EOF

    chmod -R 777 /app

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
