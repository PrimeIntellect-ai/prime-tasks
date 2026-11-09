#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gnuplot
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/experiment.csv
Time,[B]
0,0.000000
1,0.287500
2,0.362100
3,0.354800
4,0.320400
5,0.279800
6,0.241500
7,0.207800
8,0.179000
9,0.154600
10,0.134000
EOF

    chmod -R 777 /home/user
