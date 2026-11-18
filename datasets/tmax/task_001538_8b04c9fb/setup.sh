#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip unzip tar gzip coreutils util-linux findutils
    pip3 install pytest

    mkdir -p /home/user/docs_drop
    mkdir -p /tmp/docs_staging/api/v1
    mkdir -p /tmp/docs_staging/guides

    echo "# API V1 Endpoints" > /tmp/docs_staging/api/v1/endpoints.md
    echo "Authentication guide" > /tmp/docs_staging/api/v1/auth.md
    echo "Welcome to the system" > /tmp/docs_staging/readme.md
    echo "User guide details" > /tmp/docs_staging/guides/user_guide.md

    cd /tmp/docs_staging
    zip -r nested_api.zip api/
    rm -rf api/

    tar -czf /tmp/main_docs.tar.gz readme.md guides/ nested_api.zip

    split -b 200 /tmp/main_docs.tar.gz /home/user/docs_drop/docs_archive.tar.gz.part

    rm -rf /tmp/docs_staging /tmp/main_docs.tar.gz

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
