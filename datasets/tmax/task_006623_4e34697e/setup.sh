#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sensor_data.csv
id,x,y,value
1,0.0,0.0,50.0
2,10.0,0.0,60.0
3,0.0,10.0,40.0
4,5.0,5.0,
5,100.0,100.0,
6,101.0,100.0,85.0
7,100.0,101.0,95.0
8,99.0,100.0,98.0
9,10.0,10.0,
EOF

    cat << 'EOF' > /home/user/.expected_sensor_data.csv
id,x,y,value
1,0.0,0.0,50.0
2,10.0,0.0,60.0
3,0.0,10.0,40.0
4,5.0,5.0,50.00
5,100.0,100.0,REJECTED
6,101.0,100.0,85.0
7,100.0,101.0,95.0
8,99.0,100.0,98.0
9,10.0,10.0,50.00
EOF

    chmod -R 777 /home/user
