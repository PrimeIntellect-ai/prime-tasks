#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip unzip tar
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/configs_setup
    cd /home/user/configs_setup

    # Create dummy contents
    mkdir -p app1 app2
    echo "port=8080" > app1/server.conf
    echo "db=mysql" > app1/db.conf
    dd if=/dev/urandom of=app1/binary_data.bin bs=1K count=1 2>/dev/null

    echo "workers=4" > app2/celery.conf
    dd if=/dev/urandom of=app2/image.png bs=1K count=1 2>/dev/null

    # Create nested zips
    cd app1 && zip -r ../app1_backup.zip ./* && cd ..
    cd app2 && zip -r ../app2_backup.zip ./* && cd ..

    # Create outer tar
    tar -czf /home/user/incoming_configs.tar.gz app1_backup.zip app2_backup.zip

    # Cleanup setup dir
    cd /home/user
    rm -rf /home/user/configs_setup

    chmod -R 777 /home/user
