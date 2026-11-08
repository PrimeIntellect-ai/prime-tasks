#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/sensor_x.csv
id,val_x
1,1.5
2,2.3
3,3.1
4,4.0
5,5.2
6,6.1
7,7.0
8,8.5
9,9.2
10,10.1
EOF

    cat << 'EOF' > /home/user/sensor_y.csv
id,val_y
3,2.9
1,1.4
10,9.9
5,5.1
4,4.1
8,8.3
2,2.0
9,8.9
7,7.2
6,5.8
EOF

    chmod -R 777 /home/user
