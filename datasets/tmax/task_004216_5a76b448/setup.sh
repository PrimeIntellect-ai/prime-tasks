#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/dataset.txt
System anomaly detected in node A. Anomaly resolved. No anomaly in node B. All systems normal.
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
