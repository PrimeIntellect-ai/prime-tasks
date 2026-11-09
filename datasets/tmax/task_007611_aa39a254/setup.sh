#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    mkdir -p /home/user/src

    cat << 'EOF' > /home/user/data/test_data.txt
2.0
2.5
3.0
4.0
5.0
EOF

    cat << 'EOF' > /home/user/data/target_data.txt
5.0
6.2
7.1
8.5
10.0
12.4
15.0
20.2
25.0
40.0
EOF

    chmod -R 777 /home/user
