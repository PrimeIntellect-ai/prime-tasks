#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas matplotlib

    mkdir -p /home/user

    cat << 'EOF' > /home/user/demographics.csv
user_id,age
1,25
2,30
3,22
4,35
5,28
EOF

    cat << 'EOF' > /home/user/activity.csv
uid,event_type,latency_ms
1,click,100
1,view,150
2,click,200
3,view,50
4,click,300
4,click,310
5,view,120
5,view,130
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
