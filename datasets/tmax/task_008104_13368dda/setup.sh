#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk bc coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user

    cat << 'EOF' > /home/user/P.txt
0.2
0.2
0.2
0.2
0.2
EOF

    cat << 'EOF' > /home/user/Q.txt
0.1
0.2
0.3
0.2
0.2
EOF

    chmod -R 777 /home/user
