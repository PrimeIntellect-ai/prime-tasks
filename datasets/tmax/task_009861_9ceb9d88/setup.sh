#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libopenblas-dev gawk
    pip3 install pytest

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/embeddings.csv
id,v1,v2,v3
1,1.0,0.0,0.0
2,0.9,0.1,0.0
3,0.0,1.0,0.0
4,0.0,0.9,0.1
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
