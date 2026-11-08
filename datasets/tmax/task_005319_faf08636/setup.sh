#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils sed grep
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/sourceA.csv
id,f1,f2
1,A,10
2,B,20
3,C,30
4,D,40
5,E,50
6,F,60
7,G,70
8,H,80
EOF

    cat << 'EOF' > /home/user/sourceB.csv
id,f3,pred
1,A,100
2,B,200.0
3,C,
4,D,400
5,E,-500
6,F,600.5
7,G,700
8,H,
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
