#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/wt_data.csv
t,x1,x2,y
1,1.0,0.5,2.1
2,2.0,0.8,3.9
3,3.0,1.5,6.2
4,4.0,2.1,8.0
5,5.0,2.9,10.5
6,6.0,3.3,12.2
7,7.0,4.1,14.5
8,8.0,4.8,16.6
9,9.0,5.6,18.9
10,10.0,6.2,21.0
EOF

    cat << 'EOF' > /home/user/mut_data.csv
t,x1,x2,y
1,1.0,1.001,2.0
2,2.0,2.002,4.0
3,3.0,3.003,6.0
4,4.0,4.004,8.0
5,5.0,5.005,10.0
6,6.0,6.006,12.0
7,7.0,7.007,14.0
8,8.0,8.008,16.0
9,9.0,9.009,18.0
10,10.0,10.010,20.0
EOF

    chmod -R 777 /home/user
