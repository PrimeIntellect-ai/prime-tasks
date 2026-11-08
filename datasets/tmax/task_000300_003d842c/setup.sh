#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc make libc6-dev
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/transactions.csv
tx_id,waits_for_tx_id
10,20
20,30
30,40
40,50
50,60
60,70
70,30
80,10
90,80
100,110
110,120
EOF

cat << 'EOF' > /home/user/costs.csv
tx_id,cost
10,100
20,150
30,200
40,250
50,300
60,350
70,400
80,50
90,75
100,500
110,600
120,700
EOF

chmod -R 777 /home/user
