#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest pandas numpy

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/config_history.csv
time,server,cpu_cores,memory_max,disk_gb
2023-11-01T10:00:00Z,srv-1,16,1024,100
2023-11-01T10:05:00Z,srv-2,32,2048,500
2023-11-01T11:00:00Z,srv-1,32,2048,
2023-11-01T11:30:00Z,srv-1,8,4096,
2023-11-01T12:00:00Z,srv-1,256,8192,
2023-11-01T12:30:00Z,srv-1,16,65536,
2023-11-01T13:00:00Z,srv-2,,4096,
2023-11-01T14:00:00Z,srv-1,,1024,
2023-11-01T15:00:00Z,srv-3,4,512,50
EOF

chmod -R 777 /home/user
