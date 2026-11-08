#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bc gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/patients.csv
ID,Age,BloodPressure
1,45,120
2,invalid,135
3,60,150
4,30,110
5,100,200
6,50,
7,,130
8,48,135
9,35,140
10,65.5,130
EOF

    chown -R user:user /home/user/data
    chmod -R 777 /home/user
