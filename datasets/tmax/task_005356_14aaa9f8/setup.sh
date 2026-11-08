#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cat << 'LOGEOF' > /home/user/raw_sensors.log
[2023-11-01 10:00:00] [INFO] Sensor: 10 Temp: 40C Humidity: 50%
[2023-11-01 10:05:00] [CRITICAL] Sensor: 11 Temp: 90C Humidity: 85%
[2023-11-01 10:10:00] [WARNING] Sensor: 12 Temp: 75C Humidity: 60%
[2023-11-01 10:15:00] [CRITICAL] Sensor: 13 Temp: 94C Humidity: 88%
[2023-11-01 10:20:00] [CRITICAL] Sensor: 14 Temp: 98C Humidity: 90%
[2023-11-01 10:25:00] [ERROR] Sensor: 15 Temp: 85C Humidity: 80%
LOGEOF

    chmod -R 777 /home/user
