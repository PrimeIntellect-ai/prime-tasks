#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/t1_positions.csv
id,x,y,z
D01,0.0,0.0,0.0
D02,10.0,5.0,2.0
D03,5.0,5.0,5.0
D05,100.0,200.0,300.0
EOF

    cat << 'EOF' > /home/user/t2_positions.csv
id,x,y,z
D01,3.0,4.0,0.0
D02,10.0,5.0,2.0
D04,1.0,1.0,1.0
D05,100.0,200.0,310.0
D06,0.0,0.0,0.0
EOF

    chmod -R 777 /home/user
