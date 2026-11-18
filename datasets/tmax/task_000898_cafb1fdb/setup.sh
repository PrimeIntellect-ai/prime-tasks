#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk bc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cat << 'EOF' > /home/user/raw_sensors.csv
id,x,y,z,timestamp
1,1.0,2.0,2.0,1001
2,10.0,10.0,10.0,1002
3,0.0,3.0,4.0,1003
4,2.0,2.0,1.0,1004
5,0.0,0.0,0.0,1005
6,5.0,0.0,12.0,1006
7,6.0,8.0,0.0,1007
8,-1.0,-2.0,-2.0,1008
9,3.0,4.0,0.0,1009
10,-6.0,-8.0,0.0,1010
11,2.0,3.0,6.0,1011
12,1.0,1.0,1.0,1012
13,8.0,6.0,0.0,1013
14,0.0,5.0,12.0,1014
15,100.0,0.0,0.0,1015
EOF

    chmod -R 777 /home/user
