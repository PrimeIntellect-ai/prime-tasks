#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/server_logs.csv
105,U01,192.168.1.2,
100,U01,192.168.1.1,150
110,U01,192.168.1.3,200
101,U02,10.0.0.1,
106,U02,10.0.0.2,300
100,U03,172.16.0.1,500
108,U03,172.16.0.2,
115,U03,172.16.0.3,
102,U04,8.8.8.8,400
103,U04,8.8.4.4,200
104,U04,1.1.1.1,
EOF

    chmod -R 777 /home/user
