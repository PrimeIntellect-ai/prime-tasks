#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc git cron locales gawk
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/telemetry_data
echo "23.5, 45.1, 99.8" > /home/user/telemetry_data/sensor_a.dat
echo "11.1, 22.2" > /home/user/telemetry_data/sensor_b.dat

chmod -R 777 /home/user
chmod 644 /home/user/telemetry_data/sensor_a.dat
chmod 600 /home/user/telemetry_data/sensor_b.dat
chown -R user:user /home/user/telemetry_data
