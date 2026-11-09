#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/logs

    cat << 'EOF' > /home/user/logs/log1.csv
timestamp_ms,user_id,action,value
100000,U100,LOGIN,1
102000,U100,LOGIN,1
110000,U100,CLICK,5
160000,U600,LOGIN,1
170000,U700,LOGIN,1
EOF

    cat << 'EOF' > /home/user/logs/log2.csv
timestamp_ms,user_id,action,value
108000,U100,CLICK,5
115000,U200,LOGIN,1
116000,U200,LOGOUT,1
130000,U300,LOGIN,1
140000,U400,LOGIN,1
150000,U500,LOGIN,1
EOF

    cat << 'EOF' > /home/user/expected_processed_logs.csv
timestamp_sec,masked_user_id,action,value
100,MASKED_100,LOGIN,1
108,MASKED_100,CLICK,5
115,MASKED_200,LOGIN,1
116,MASKED_200,LOGOUT,1
130,MASKED_300,LOGIN,1
140,MASKED_400,LOGIN,1
150,MASKED_500,LOGIN,1
160,MASKED_600,LOGIN,1
170,MASKED_700,LOGIN,1
EOF

    chmod -R 777 /home/user
