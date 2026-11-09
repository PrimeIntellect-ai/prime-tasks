#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cat << 'EOF' > /home/user/raw_logs.csv
user_id,item_id,action_type,timestamp
u1,i1,purchase,1000
u1,i1,purchase,1005
u1,i2,purchase,1010
u2,i1,purchase,1020
u2,i2,purchase,1030
u2,i3,purchase,1040
u3,i1,purchase,1050
u3,i4,purchase,1060
u4,i2,purchase,1070
u4,i3,purchase,1080
u5,i1,purchase,1090
u5,i2,purchase,1100
u5,i4,purchase,1110
u6,i5,view,1120
u6,i1,view,1130
u7,i6,purchase,1140
EOF

    chmod -R 777 /home/user
