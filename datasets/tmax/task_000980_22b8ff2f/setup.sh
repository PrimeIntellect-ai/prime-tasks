#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/reference.csv
time,signal
1.0,2.1
2.0,4.0
3.0,6.1
4.0,8.0
5.0,10.0
EOF

    cat << 'EOF' > /home/user/data/raw.csv
time,signal
1.0,2.0
2.0,3.9
3.0,15.0
4.0,8.2
5.0,9.9
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
