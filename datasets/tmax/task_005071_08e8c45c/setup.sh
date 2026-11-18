#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/features.csv
1.5,2.3,3.1
2.5,1.1,4.2
3.5,3.4,1.3
4.5,5.2,2.4
5.5,4.8,5.5
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
