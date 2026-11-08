#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git cron
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/device_data
    echo "sensor_val=42" > /home/user/device_data/sensor.conf
    echo "status=active" > /home/user/device_data/state.log
    chown -R user:user /home/user/device_data

    chmod -R 777 /home/user
