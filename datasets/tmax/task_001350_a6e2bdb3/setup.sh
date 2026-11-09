#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils sed
    pip3 install pytest

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/measurements.csv
id,spring_id,displacement
1,A,0.1
2,A,0.2
3,A,0.3
4,B,0.15
5,B,0.25
6,B,0.35
7,C,0.05
8,C,0.10
9,C,0.15
EOF

    cat << 'EOF' > /home/user/data/forces.csv
id,force
1,2.1
2,4.0
3,5.9
4,12.0
5,20.0
6,28.0
7,2.5
8,5.0
9,7.5
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
