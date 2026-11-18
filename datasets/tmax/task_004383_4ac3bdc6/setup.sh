#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip cron
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/incoming /home/user/output

cat << 'EOF' > /home/user/incoming/data.csv
timestamp,hostname,metric_name,value,message
2023-10-12 08:15:30,server-a,memory_leak_bytes,1024,"Error occurred
at module A
Traceback: None"
2023-10-12 08:45:10,server-a,memory_leak_bytes,2048,"Another error"
2023-10-12 08:20:00,server-b,memory_leak_bytes,512,"All good"
2023-10-12 09:05:00,server-a,memory_leak_bytes,4096,"Crash
dump
saved"
2023-10-12 09:10:00,server-a,cpu_usage,99,"High CPU
ignore this line"
2023-10-12 09:30:00,server-b,memory_leak_bytes,8192,"Oops"
2023-10-12 09:55:00,server-b,memory_leak_bytes,4000,"Warning"
EOF

chmod -R 777 /home/user
