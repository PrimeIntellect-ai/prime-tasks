#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk bc sed grep coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/thermal_profile.txt
0 10 100 5 1000
1 12 96 4 1100
2 15 93 4 1200
3 11 90 5 1250
4 10 87 6 1300
5 14 85 4 1350
6 12 82 5 1400
7 11 80 4 1450
8 13 78 5 1500
9 15 76 6 1550
EOF

    chmod -R 777 /home/user
