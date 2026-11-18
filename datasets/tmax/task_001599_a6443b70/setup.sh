#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/sensor_data.csv
1.25
2.40
0.75
-0.50
1.10
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
