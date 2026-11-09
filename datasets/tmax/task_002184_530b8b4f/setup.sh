#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip rustc cargo tar gzip gawk grep
pip3 install pytest

mkdir -p /home/user/telemetry_data
echo '{"sensor_id": 1, "temp": 45.2}' > /home/user/telemetry_data/sensor_1.json
echo '{"sensor_id": 2, "temp": 48.9}' > /home/user/telemetry_data/sensor_2.json
echo "INFO: System boot normal" > /home/user/device_health.log
echo "INFO: Network connected" >> /home/user/device_health.log
echo "CRITICAL: Thermal throttling engaged" >> /home/user/device_health.log

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
