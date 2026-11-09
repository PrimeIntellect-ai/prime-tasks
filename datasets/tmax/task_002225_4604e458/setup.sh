#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/formulas.txt
ALPHA = 25 + 3 * (12 - 4)
BETA = ALPHA * 2 - 15
compute(x) = x * x * x - ALPHA * x + BETA
EOF

    chmod -R 777 /home/user
