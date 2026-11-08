#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git gcc libc6-dev procps tzdata
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_data.txt
1700000000 24.5
1700000005 88.1 ANOMALY
1700000010 23.9
1700000015 95.0 ANOMALY
1700000020 24.1
EOF

    chmod -R 777 /home/user
