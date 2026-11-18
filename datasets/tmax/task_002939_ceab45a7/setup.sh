#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest pandas numpy

    mkdir -p /home/user/sensor
    cat << 'EOF' > /home/user/sensor_data.csv
X,Y
0.0,2.1
1.0,5.6
2.0,9.1
3.0,12.6
4.0,16.1
5.0,100.0
6.0,23.1
7.0,26.6
8.0,30.1
9.0,33.6
10.0,37.1
11.0,40.6
12.0,44.1
13.0,47.6
14.0,51.1
15.0,-50.0
16.0,58.1
17.0,61.6
18.0,65.1
19.0,68.6
20.0,72.1
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/sensor /home/user/sensor_data.csv
    chmod -R 777 /home/user
