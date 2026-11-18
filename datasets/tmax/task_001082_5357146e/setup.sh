#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cron
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/images
    dd if=/dev/zero of=/home/user/images/edge_device.img bs=1M count=10
    chown -R user:user /home/user/images

    chmod -R 777 /home/user
