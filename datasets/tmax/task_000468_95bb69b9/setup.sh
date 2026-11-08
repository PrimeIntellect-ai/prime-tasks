#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils sed
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/dataset.csv
10.5,20.0,30.5
12.0,18.5,35.0
9.5,22.0,28.0
11.0,19.5,31.5
15.0,25.0,40.0
EOF

    chmod -R 777 /home/user
