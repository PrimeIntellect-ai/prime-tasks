#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/legacy_metrics.csv
timestamp,cpu_util,memory_util
1600000000,10.0,80.1
1600000060,20.0,81.0
1600000120,30.0,82.5
1600000180,20.0,80.0
1600000240,10.0,79.5
EOF

    chmod -R 777 /home/user
