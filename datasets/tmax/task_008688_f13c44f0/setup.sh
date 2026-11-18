#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential gawk
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /home/user/src

    cat << 'EOF' > /home/user/data/features.csv
id,x,y,z
1,0.6394,0.0250,0.2750
2,0.2232,0.7365,0.6767
3,0.8922,0.0869,0.4219
4,0.0298,0.2186,0.5054
5,0.0265,0.1988,0.6499
6,0.5450,0.1346,0.9990
7,0.7584,0.2520,0.4079
8,0.1406,0.8351,0.2612
9,0.0385,0.6974,0.0898
10,0.5053,0.3013,0.3477
EOF

    cat << 'EOF' > /home/user/data/labels.csv
id,label
1,0
2,1
3,1
4,0
5,0
6,1
7,1
8,0
9,0
10,0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
