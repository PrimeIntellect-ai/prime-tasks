#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/telemetry_data
    dd if=/dev/zero of=/home/user/telemetry_data/sensor.dat bs=1M count=45
    touch /home/user/.bashrc

    chmod -R 777 /home/user
