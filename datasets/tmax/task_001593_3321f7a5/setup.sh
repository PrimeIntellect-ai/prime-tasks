#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/users.csv
id,age,score1,score2
U100,25,0.8,0.5
U101,30,0.5,0.9
U102,40,0.1,0.2
EOF

    cat << 'EOF' > /home/user/candidates.csv
cand_id,age,score1,score2
C1,24,0.7,0.6
C2,35,0.2,0.1
C3,26,0.9,0.5
C4,25,0.7,0.9
C5,40,0.2,0.2
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
