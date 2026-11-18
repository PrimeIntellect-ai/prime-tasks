#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/data.csv
10.2
11.5
9.8
10.5
12.1
9.5
10.8
11.1
10.0
10.9
EOF

    chmod -R 777 /home/user
