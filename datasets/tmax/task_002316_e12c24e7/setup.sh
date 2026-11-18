#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/users.csv
user_id,group,feature_a,feature_b,feature_c
U_TARGET,Control,10.0,20.0,30.0
U_1,Treatment,10.5,20.1,30.5
U_2,Control,10.0,-9999,30.0
U_3,Treatment,NaN,20.0,30.0
U_4,Control,11.0,21.0,31.0
U_5,Treatment,8.0,18.0,28.0
U_6,Control,10.1,20.1,30.1
U_7,Treatment,100.0,200.0,300.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
