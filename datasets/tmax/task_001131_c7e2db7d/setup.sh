#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cat << 'EOF' > /home/user/signal.csv
10.5
12.1
NaN
11.8

13.2
100.0
9.4
11.1
-50.0
12.5
EOF

    chmod -R 777 /home/user
