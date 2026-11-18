#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils sed
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cat << 'EOF' > /home/user/signal.txt
10000000000000000.0
-10000000000000000.0
1.0
2.0
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
