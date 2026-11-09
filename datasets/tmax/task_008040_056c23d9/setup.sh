#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install task-specific dependencies
    apt-get install -y qemu-utils logrotate golang

    # Create user
    useradd -m -s /bin/bash user || true

    # Create task directory and dummy data
    mkdir -p /home/user/legacy_vms
    cd /home/user/legacy_vms
    qemu-img create -f qcow2 web_server.qcow2 15G
    qemu-img create -f qcow2 db_server.qcow2 30G
    qemu-img create -f qcow2 cache_server.qcow2 10G

    # Set permissions
    chown -R user:user /home/user
    chmod -R 777 /home/user
