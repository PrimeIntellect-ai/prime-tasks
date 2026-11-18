#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/config_changes.log
[2023-10-24 14:05:12] USER:admin CONFIG:max_connections=500
[2023-10-24 14:10:00] USER:system CONFIG:timeout=30
[2023-10-24 14:23:01] USER:admin CONFIG:max_connections=500
[2023-10-24 14:59:59] USER:deploy CONFIG:feature_flag_x=true
[2023-10-24 15:01:00] USER:admin CONFIG:max_connections=600
[2023-10-24 15:15:30] USER:system CONFIG:timeout=30
[2023-10-24 15:30:00] USER:admin CONFIG:feature_flag_x=false
[2023-10-24 15:35:00] USER:admin CONFIG:max_connections=600
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
