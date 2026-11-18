#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sensor_data.csv
sensor_id,successes,trials
1,10,20
2,15,30
3,,25
4,5,10
5,,40
EOF

    chmod -R 777 /home/user
