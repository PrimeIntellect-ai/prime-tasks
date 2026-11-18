#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk bc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sensor_data.csv
id,v1,v2
1,10.5,15.2
2,12.1,14.8
3,8.4,11.1
4,15.0,20.0
5,9.2,10.5
6,14.5,19.2
7,11.1,12.2
8,13.3,16.5
9,10.0,14.0
10,12.5,15.5
EOF

    chmod -R 777 /home/user
