#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/train.csv
1.0, 2.0
3.0, -9999.0
5.0, 6.0
-9999.0, 8.0
9.0, 10.0
EOF

    cat << 'EOF' > /home/user/test.csv
2.0, 4.0
-9999.0, 5.0
8.0, -9999.0
EOF

    chmod -R 777 /home/user
