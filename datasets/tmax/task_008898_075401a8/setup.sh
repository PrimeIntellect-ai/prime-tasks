#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang zip tar
    pip3 install pytest

    mkdir -p /home/user/incoming
    mkdir -p /home/user/configs

    # Create a safe zip
    mkdir -p /tmp/safe
    echo "port=8080" > /tmp/safe/app.conf
    echo "host=localhost" > /tmp/safe/db.conf
    cd /tmp/safe && zip -r /tmp/safe.zip ./*

    # Create a malicious zip (Zip Slip)
    mkdir -p /tmp/malicious
    echo "malicious payload" > /tmp/malicious/escaped.conf
    cd /tmp/malicious
    # using python to create a zip with a directory traversal path
    python3 -c "
import zipfile
with zipfile.ZipFile('/tmp/malicious.zip', 'w') as zf:
    zf.writestr('../../user/escaped.conf', 'malicious payload')
    zf.writestr('safe_in_malicious.conf', 'safe payload')
"

    # Package them into a tar.gz
    cd /tmp
    tar -czf /home/user/incoming/update.tar.gz safe.zip malicious.zip
    rm -rf /tmp/safe /tmp/safe.zip /tmp/malicious /tmp/malicious.zip

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
