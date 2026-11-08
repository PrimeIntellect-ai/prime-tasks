#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/raw_measurements.txt
X-1 | p1: 10.0C, p2: 12.5 C, p1: 9.0C, p3: N/A
X-2 | p1: 11.1C, p2: err
X-1 | p1: 10.5C, p4: 14.2C
X-3 | p5: 5.5C, p5: 5.5c
Y-9 | m1: -4.5 C, m2: 0.0C, m1: -2.0c
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
