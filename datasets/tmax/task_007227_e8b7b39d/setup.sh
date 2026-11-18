#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/features_a.txt
3 1.0
1 2.0
2 3.5
5 -2.0
4 0.0
EOF

    cat << 'EOF' > /home/user/features_b.txt
2 1.0
5 3.0
1 0.5
4 -1.5
3 -1.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
