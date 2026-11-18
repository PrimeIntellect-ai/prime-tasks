#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make libc6-dev
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/system.txt
4.0 1.0 1.0 9.0
1.0 3.0 0.0 7.0
0.0 1.0 2.0 8.0
EOF

    cat << 'EOF' > /home/user/gc_data.txt
0.80
0.90
0.95
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
