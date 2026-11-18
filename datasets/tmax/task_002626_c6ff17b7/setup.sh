#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/citations.csv
1,2
2,3
1,4
4,3
3,5
6,2
7,8
8,9
7,9
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
