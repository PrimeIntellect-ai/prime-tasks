#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest networkx pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/ownership.csv
source,target,weight
I_1,C_1,100
I_2,C_2,50
I_3,C_2,50
C_1,C_3,60
C_2,C_3,40
C_3,C_4,100
C_4,C_5,80
C_2,C_5,20
C_5,C_6,100
EOF

    chmod -R 777 /home/user
