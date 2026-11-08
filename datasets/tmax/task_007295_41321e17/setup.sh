#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc gawk build-essential
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/sensors.csv
1.5,2.5,3.5
1.5,2.5,3.9
10.0,0.0,0.0
0.0,10.0,0.0
5.5,5.5,5.5
20.0,0.0,0.0
0.0,20.0,0.0
7.0,7.0,7.0
8.0,8.0,8.0
15.0,15.0,15.0
11.0,0.0,0.0
EOF

chmod -R 777 /home/user
