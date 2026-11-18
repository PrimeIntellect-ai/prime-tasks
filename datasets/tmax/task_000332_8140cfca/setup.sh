#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /tmp/task_setup/state_01/etc/app/
    mkdir -p /tmp/task_setup/state_03/opt/service/config/
    mkdir -p /tmp/task_setup/state_04/var/lib/app/

    echo "PORT=8080" > /tmp/task_setup/state_01/etc/app/settings.conf
    echo "MAX_CONNECTIONS=150" >> /tmp/task_setup/state_01/etc/app/settings.conf

    echo "PORT=8080" > /tmp/task_setup/state_03/opt/service/config/settings.conf
    echo "MAX_CONNECTIONS=200" >> /tmp/task_setup/state_03/opt/service/config/settings.conf

    echo "PORT=8080" > /tmp/task_setup/state_04/var/lib/app/settings.conf
    echo "MAX_CONNECTIONS=500" >> /tmp/task_setup/state_04/var/lib/app/settings.conf

    cd /tmp/task_setup/state_01 && tar -czf ../state_01.tar.gz .
    cd /tmp/task_setup/state_03 && tar -czf ../state_03.tar.gz .
    cd /tmp/task_setup/state_04 && tar -czf ../state_04.tar.gz .

    # Create a corrupt archive
    dd if=/dev/urandom of=/tmp/task_setup/state_02.tar.gz bs=1024 count=10

    cd /tmp/task_setup
    tar -cf /home/user/server_history.tar state_01.tar.gz state_02.tar.gz state_03.tar.gz state_04.tar.gz
    rm -rf /tmp/task_setup

    chmod -R 777 /home/user
