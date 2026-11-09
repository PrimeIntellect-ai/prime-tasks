#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/transitions.log
Initializing system...
[SEQ] State: START Action: INIT Weight: 10 Next: NODE_A
System check passed.
[SEQ] State: NODE_A Action: JUMP Weight: -3 Next: NODE_B
[SEQ] State: NODE_B Action: CRANK Weight: 15 Next: NODE_C
[DEBUG] Warning: high temp
[SEQ] State: NODE_C Action: SLIDE Weight: 4 Next: NODE_X
[SEQ] State: NODE_D Action: INVALID Weight: 99 Next: NODE_E
[SEQ] State: NODE_X Action: JUMP Weight: 1 Next: NODE_Y
EOF

    chmod -R 777 /home/user
