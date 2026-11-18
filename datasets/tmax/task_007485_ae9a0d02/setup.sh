#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk bc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_data.csv
A,B,C,D
1,2.1,5.5,X
2,4.0,6.1,Y
3,6.2,5.9,Z
invalid,row,here,1
4,8.1,4.2,W
-1.5,-3.0,5.0,V
5,10.0,missing,U
6,11.9,4.8,T
10,20.1,5.2,S
EOF

    chmod -R 777 /home/user
