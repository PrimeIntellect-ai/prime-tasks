#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/reference.csv
Node,Frequency
0,0.201000
1,0.198000
2,0.205000
3,0.196000
4,0.200000
EOF

    chmod -R 777 /home/user
