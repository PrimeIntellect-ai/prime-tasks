#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/instances.txt
data-processor-1 2.45
ml-training-node 8.90
cache-replica 1.10
etl-worker-a 3.50
etl-worker-b 3.50
log-aggregator 0.85
EOF

    chmod -R 777 /home/user
