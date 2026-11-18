#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential cron
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sensor_data.csv
1620000000,70.0,80
1620000060,71.0,85
1620000180,75.0,40
1620000240,80.0,30
1620000300,90.0,20
1620000360,95.0,10
1620000480,92.0,5
EOF

    chmod -R 777 /home/user
