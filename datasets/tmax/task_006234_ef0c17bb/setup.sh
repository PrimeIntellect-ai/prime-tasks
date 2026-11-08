#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget curl time bc gawk coreutils
    pip3 install pytest

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/set_A.json
{
  "numbers": [991, 10, 42, 77, 256, 1024, 2048, 55, 3, 17, 88, 100]
}
EOF

    cat << 'EOF' > /home/user/data/set_B.json
{
  "numbers": [1024, 5, 8, 42, 100, 33, 991, 2000, 17]
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
