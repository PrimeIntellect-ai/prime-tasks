#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/backup

    cat << 'EOF' > /home/user/backup/edges.csv
1,2
1,3
1,4
1,5
2,3
3,1
4,3
5,3
3,6
6,4
6,7
6,8
6,9
6,10
EOF

    chmod -R 777 /home/user
