#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/daily_etl.csv
user_id,session_time,click_count,bounce_rate,revenue
101,12.5,2,0.5,100
102.0,5.0,8,0.1,250
NaN,3.2,9,0.9,0
104,8.1,3,0.4,150
105,9.9,7,0.2,200
106.0,1.1,10,0.8,300
107,4.4,1,0.1,50
108.0,6.6,12,0.5,150
109,7.7,4,0.3,90
EOF

    chmod -R 777 /home/user
