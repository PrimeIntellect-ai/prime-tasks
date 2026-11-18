#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user

cat << 'EOF' > /home/user/users.csv
user_id,f1,f2,f3
1,10.0,2.0,3.5
2,5.0,1.0,0.0
3,8.0,8.0,8.0
4,1.0,2.0,3.0
5,20.0,0.0,1.0
6,15.0,10.0,5.0
7,50.0,0.0,0.0
8,12.5,12.5,0.0
9,0.0,0.0,0.0
EOF

cat << 'EOF' > /home/user/weights.csv
user_id,w1,w2,w3
5,2.0,1.0,1.0
1,1.0,0.5,2.0
8,2.0,2.0,1.0
4,10.0,10.0,10.0
2,1.0,1.0,1.0
3,2.0,2.0,2.0
7,1.0,1.0,1.0
6,2.0,2.0,2.0
9,100.0,100.0,100.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
