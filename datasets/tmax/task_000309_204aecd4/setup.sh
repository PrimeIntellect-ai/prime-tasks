#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils sed
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/source1.csv
id,feature_x
1,10.0
2,20.0
3,
4,30.0
5,100.0
6,-10.0
7,15.0
8,-60.0
9,5.0
10,25.0
EOF

    cat << 'EOF' > /home/user/source2.csv
id,feature_y
4,28.0
1,12.0
2,18.0
3,25.0
5,10.0
6,-5.0
7,
8,-10.0
9,8.0
10,22.0
EOF

    chmod 644 /home/user/source1.csv /home/user/source2.csv

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
