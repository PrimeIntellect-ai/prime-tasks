#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest jupyter nbconvert

    mkdir -p /home/user

    cat << 'EOF' > /home/user/population_data.csv
t,P
0,10.0
10,61.5
20,242.0
30,370.0
40,395.0
50,399.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
