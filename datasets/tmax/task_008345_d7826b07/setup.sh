#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk bc coreutils
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/model.conf
bias=1.0
w1=2.0
w2=3.0
EOF

    cat << 'EOF' > /home/user/data_A.csv
id,f1
3,1.0
10,10.0
1,1.0
4,2.0
8,2.0
2,2.0
5,3.0
7,3.0
9,3.0
6,1.0
EOF

    cat << 'EOF' > /home/user/data_B.csv
id,f2
9,2.0
3,2.0
2,2.0
5,3.0
1,1.0
8,3.0
10,10.0
6,3.0
4,1.0
7,1.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
