#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc cron
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/logs
mkdir -p /home/user/output
mkdir -p /home/user/logs/archive

cat << EOF > /home/user/logs/srv_a.log
timestamp,cpu_usage
10,45.50
20,50.00
30,55.00
40,60.25
50,65.00
EOF

cat << EOF > /home/user/logs/srv_b.log
timestamp,mem_usage
15,100.00
35,200.00
60,300.00
EOF

chown -R user:user /home/user/logs
chown -R user:user /home/user/output

chmod -R 777 /home/user
