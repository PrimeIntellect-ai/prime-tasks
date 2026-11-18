#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/versions.txt
2.1.0
1.2.3
1.10.1
1.2.14
0.9.9
2.0.0
10.0.1
2.10.0
10.0.0
EOF

    chmod -R 777 /home/user
