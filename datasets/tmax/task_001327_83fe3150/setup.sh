#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scikit-learn

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/train.csv
id,category_id,v1,v2,target
1,10,0.5,1.2,0
2,,0.6,1.1,0
3,20,1.5,0.2,1
4,10,0.4,1.3,0
5,,1.6,0.1,1
6,20,1.4,0.3,1
7,30,0.9,0.9,0
EOF

    cat << 'EOF' > /home/user/test.csv
id,category_id,v1,v2
8,10,0.55,1.25
9,,0.7,1.0
10,20,1.45,0.25
11,40,0.8,0.8
EOF

    chmod -R 777 /home/user
