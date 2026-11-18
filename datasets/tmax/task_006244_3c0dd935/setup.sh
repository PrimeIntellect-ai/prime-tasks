#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy networkx

    mkdir -p /home/user

    cat << 'EOF' > /home/user/exons.txt
E1 100
E2 50
E3 200
E4 150
EOF

    cat << 'EOF' > /home/user/transcripts.txt
T1 E1,E2,E4
T2 E1,E3,E4
T3 E1,E4
EOF

    cat << 'EOF' > /home/user/coverage.txt
E1 3520
E2 490
E3 2030
E4 5200
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
