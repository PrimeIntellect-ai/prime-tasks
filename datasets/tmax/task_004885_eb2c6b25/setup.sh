#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/transition_graph.txt
A B 0.6
A C 0.4
B A 0.3
B C 0.7
C A 0.5
C B 0.5
EOF

    cat << 'EOF' > /home/user/empirical.txt
A 0.30
B 0.35
C 0.35
EOF

    chmod -R 777 /home/user
