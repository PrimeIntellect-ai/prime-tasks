#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ socat curl gawk jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/public_html

    cat << 'EOF' > /home/user/raw_requests.txt
[2023-10-01] REJECTED alice alice@example.com
[2023-10-01] APPROVED bob bob@example.com
[2023-10-02] PENDING charlie charlie@example.com
[2023-10-02] APPROVED david david@example.com
[2023-10-03] APPROVED eve eve@example.com
[2023-10-03] REJECTED frank frank@example.com
EOF

    chmod -R 777 /home/user
