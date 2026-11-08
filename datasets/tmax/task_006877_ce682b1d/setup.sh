#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang git
    pip3 install pytest

    mkdir -p /home/user/ml_pipeline
    cat << 'EOF' > /home/user/features.csv
1.0,2.0,3.0
2.0,3.5,4.0
3.0,4.0,5.5
4.0,5.5,6.0
5.0,7.0,8.5
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
