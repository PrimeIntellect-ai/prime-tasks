#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    mkdir -p /home/user/dataset/archive
    mkdir -p /home/user/archiver

    yes "SENSOR_DATA_LOG_ENTRY_2023_X" | head -c 2621440 > /home/user/dataset/raw_sensor.log

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
