#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq time coreutils
    pip3 install pytest

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/payloads.txt
1.2.3 646f206e6f7420696e636c756465
1.5.0 7374617274206f662076312e35
1.11.2 686967686572206d696e6f72
2.0.1 6d616a6f7220757064617465
0.9.99 69676e6f72652074686973
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/data
    chmod -R 777 /home/user
