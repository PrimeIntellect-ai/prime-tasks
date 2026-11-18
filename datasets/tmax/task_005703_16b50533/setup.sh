#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gawk
    pip3 install pytest

    mkdir -p /home/user/raw_data

    cat << 'EOF' > /home/user/raw_data/data_1.csv
u1,admin,10
u2,user,5
u1,admin,15
u3,guest,2
EOF

    cat << 'EOF' > /home/user/raw_data/data_2.csv
u4,user,8
u5,admin,20
u2,user,9
EOF

    cat << 'EOF' > /home/user/raw_data/data_3.csv
u6,guest,1
u7,user,3
u8,admin,5
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
