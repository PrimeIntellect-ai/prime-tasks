#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/deps

    cat << 'EOF' > /home/user/deps/libs.txt
1.0.5
2.1.0
2.1.1
1.12.3
2.1.15
2.2.0
EOF

    echo "32 * 1024 + 128 - 64" > /home/user/deps/config.expr

    echo -n "Minimal container porting payload data." > /home/user/deps/payload.dat

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
