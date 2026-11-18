#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/migration/v1
    mkdir -p /home/user/migration/v2
    echo '{"db_host": "localhost", "port": 8080}' > /home/user/migration/config.json

    ln -sf /home/user/migration/config.json /home/user/migration/v1/config.json
    ln -sf /home/user/migration/v1 /home/user/app_current
    echo "DEPLOYED v1 TO /home/user/migration/v1 WITH CONFIG /home/user/migration/v1/config.json" > /home/user/deploy.log

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
