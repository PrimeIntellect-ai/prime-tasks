#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/exp1.csv
1,5
2,
3,6
4,-100
5,4
EOF

    cat << 'EOF' > /home/user/data/exp2.csv
1,
2,
3,10
4,0
EOF

    chmod -R 777 /home/user
