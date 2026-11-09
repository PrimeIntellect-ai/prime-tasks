#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scikit-learn

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/train.csv
id,category,feature_A,feature_B,target
1,X,10,1.5,20.5
2,Y,,2.0,15.0
3,X,12,1.1,22.0
4,Y,8,2.5,14.0
5,Z,5,3.0,10.0
6,Z,,3.1,10.2
7,X,11,1.3,21.0
EOF

    cat << 'EOF' > /home/user/data/test.csv
id,category,feature_A,feature_B
8,X,,1.2
9,Y,9,2.2
10,Z,,3.5
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
