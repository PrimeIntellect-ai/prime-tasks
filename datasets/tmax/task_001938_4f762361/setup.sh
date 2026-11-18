#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/researchers.csv
1,Dr. Alan Turing
2,Dr. Alonzo Church
3,Dr. Grace Hopper
4,Dr. John von Neumann
5,Dr. Claude Shannon
6,Dr. Ada Lovelace
EOF

    cat << 'EOF' > /home/user/authorship.csv
1,101
2,101
1,102
5,102
3,103
4,103
4,104
1,104
6,105
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
