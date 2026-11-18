#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/telemetry.txt
10.5
12.1
11.0
15.5
14.2
18.8
17.1
16.4
19.5
20.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
