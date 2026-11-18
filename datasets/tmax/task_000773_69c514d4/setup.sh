#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cat << 'EOF' > /home/user/artifacts.txt
1 500
2 10
3 1200
4 0
5 50
EOF

    cat << 'EOF' > /home/user/metrics.txt
1 0.02
2 0.85
3 0.05
4 0.99
5 0.70
EOF

    chmod 644 /home/user/artifacts.txt
    chmod 644 /home/user/metrics.txt

    chmod -R 777 /home/user
