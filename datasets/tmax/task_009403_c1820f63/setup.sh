#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils grep sed
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/held_locks.csv
R1,T101
R2,T102
R3,T103
R4,T104
R5,T105
R6,T106
R7,T107
EOF

    cat << 'EOF' > /home/user/requested_locks.csv
T101,R2
T102,R3
T104,R5
T105,R6
T106,R4
T108,R7
EOF

    chmod -R 777 /home/user
