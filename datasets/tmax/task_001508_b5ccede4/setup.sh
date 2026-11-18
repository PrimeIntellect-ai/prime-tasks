#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/raw_metrics.csv
timestamp,cpu_usage,memory_mb
1700000000,45,1024
1700000002,50,1048
1700000002,55,1040
1700000000,105,1000
1700000005,60,2048
1700000012,70,1024
1700000012,70,-5
1700000005,-10,2048
1700000016,15,512
EOF

chmod -R 777 /home/user
