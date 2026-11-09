#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/api_data
    mkdir -p /opt
    touch /opt/iot_image.img

    chmod -R 777 /home/user
    chmod 777 /opt/iot_image.img || true
