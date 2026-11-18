#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/incoming_configs
    echo '{"db_host": "new.local", "port": 5432}' > /home/user/incoming_configs/db.json
    echo '{"cache_size": 1024}' > /home/user/incoming_configs/cache.json

    mkdir -p /tmp/initial_config
    echo '{"db_host": "old.local", "port": 5432}' > /tmp/initial_config/db.json
    echo '{"workers": 4}' > /tmp/initial_config/web.json
    cd /tmp/initial_config && zip -r /home/user/master_config.zip db.json web.json
    rm -rf /tmp/initial_config

    chmod -R 777 /home/user
