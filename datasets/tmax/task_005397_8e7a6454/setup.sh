#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scikit-learn

    mkdir -p /home/user
    cat << 'EOF' > /home/user/raw_events.csv
user_id,age,event_code,session_duration,is_fraud
1,22,4,120.5,0
2,35,2,,0
3,42,,300.2,1
4,19,4,45.0,0
5,28,1,150.0,0
6,50,,500.5,1
7,24,2,90.0,0
8,31,4,110.0,0
9,45,1,,1
10,21,2,80.0,0
11,36,,400.0,1
12,29,4,130.0,0
13,18,1,60.0,0
14,55,2,200.0,0
15,23,,450.0,1
16,33,4,140.0,0
17,27,1,160.0,0
18,48,2,,1
19,20,4,75.0,0
20,38,1,190.0,0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
