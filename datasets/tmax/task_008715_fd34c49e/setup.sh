#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev gawk sed grep coreutils
pip3 install pytest

mkdir -p /home/user

cat << 'EOF' > /home/user/sensor_data.log
[2023-10-01 10:00] ID:A1 VALUE:1500 mV metadata ignored
[2023-10-01 10:01] ID:B2 VALUE:2.5 V info
[2023-10-01 10:02] ERROR: connection lost
[2023-10-01 10:03] ID:C3 VALUE:500 mV
[2023-10-01 10:04] ID:D4 VALUE:-1.2 V
[2023-10-01 10:05] WARNING: low battery
[2023-10-01 10:06] ID:E5 VALUE:0 V
EOF

echo "IyBEYWlseSBTZW5zb3IgUmVwb3J0ClRvdGFsIHJlY29yZHMgcHJvY2Vzc2VkOiB7e0NPVU5UfX0K" | base64 -d > /home/user/report.tmpl

useradd -m -s /bin/bash user || true
chown -R user:user /home/user
chmod -R 777 /home/user
