#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sensor_data.txt
1000000000.10
1000000000.15
1000000000.12
1000000000.18
1000000000.11
EOF

    chmod -R 777 /home/user
