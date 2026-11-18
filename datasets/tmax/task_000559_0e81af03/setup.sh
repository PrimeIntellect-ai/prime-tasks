#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip unzip tar gzip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/backups
    mkdir -p /home/user/mnt

    # Create the XML file in UTF-16LE
    echo '<?xml version="1.0" encoding="UTF-16"?><settings><database><host>db-prod-1</host><port>5432</port></database></settings>' | iconv -f UTF-8 -t UTF-16LE > /home/user/backups/app_config.xml

    # Create the JSON file in ISO-8859-1
    echo '{"services": {"cache": {"backend": "redis", "port": 6379}, "api": {"timeout": 30}}}' | iconv -f UTF-8 -t ISO-8859-1 > /home/user/backups/services.json

    # Archive the files
    cd /home/user/backups
    tar -czf configs.tar.gz app_config.xml services.json
    rm app_config.xml services.json

    chmod -R 777 /home/user
