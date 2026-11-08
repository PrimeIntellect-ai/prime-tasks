#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc sqlite3
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/data.csv
date,store_id,revenue,visitors
2023-10-01,1,100.50,50
2023-10-01,2,200.00,80
2023-10-02,1,150.25,60
2023-10-02,2,190.00,75
2023-10-03,1,120.00,55
2023-10-03,3,300.00,100
2023-10-04,3,350.50,110
EOF

chmod -R 777 /home/user
