#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/embeddings.csv
id,v1,v2,v3,v4,v5
0,0.1,0.8,0.3,0.7,0.5
1,0.9,0.1,0.1,0.2,0.1
2,0.0,1.0,0.0,1.0,0.0
3,0.5,0.5,0.5,0.5,0.5
4,0.12,0.88,0.34,0.71,0.55
5,0.2,0.7,0.4,0.6,0.6
6,0.8,0.2,0.2,0.3,0.1
7,0.11,0.85,0.33,0.70,0.54
8,0.5,0.6,0.5,0.6,0.5
9,0.1,0.1,0.1,0.1,0.1
EOF

    chmod -R 777 /home/user
