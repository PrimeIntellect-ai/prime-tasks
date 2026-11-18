#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bc gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cat << 'EOF' > /home/user/dataset.csv
id,sensor_A,sensor_B,sensor_C,target
1,12.5,4.1,88.2,15.6
2,14.0,5.0,23.1,18.0
3,11.2,3.5,56.7,13.8
4,18.5,8.2,12.4,26.4
5,16.0,6.5,45.8,22.1
6,9.5,2.0,91.3,9.7
7,13.4,4.8,34.5,17.2
8,15.1,5.6,67.8,19.5
9,17.3,7.4,8.9,24.1
10,10.8,3.0,77.6,12.5
EOF

    chmod 644 /home/user/dataset.csv
    chmod -R 777 /home/user
