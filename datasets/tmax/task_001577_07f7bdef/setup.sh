#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/observations.txt
4.1;1.0;1.01
8.2;2.0;1.98
12.0;3.0;3.05
16.5;4.0;3.95
20.1;5.0;5.02
EOF

    chmod -R 777 /home/user
