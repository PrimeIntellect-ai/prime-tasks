#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick fonts-dejavu-core
    pip3 install pytest

    # Create app directory
    mkdir -p /app/configs

    # Create config files with specific encodings
    echo "api_key=REPLACE_ME_TOKEN\nlisten=80" | iconv -f UTF-8 -t UTF-16LE > /app/configs/WEBSERVER.cfg
    echo "[db]\npass=REPLACE_ME_TOKEN\nhost=localhost" | iconv -f UTF-8 -t ISO-8859-1 > /app/configs/Database.INI
    echo "redis_url=redis://:REPLACE_ME_TOKEN@localhost:6379" > /app/configs/cache.TXT

    # Create archive and cleanup raw directory
    cd /app
    tar -czf configs.tar.gz configs
    rm -rf configs

    # Generate the server spec image
    convert -size 800x200 xc:white -fill black -pointsize 32 -gravity center -annotate +0+0 "Run server on port 9055. Use token: XyZ99_ConfigAuth" /app/server_spec.png

    # Set permissions
    chmod -R 777 /app

    # Create user and set home permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
