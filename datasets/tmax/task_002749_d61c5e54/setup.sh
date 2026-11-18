#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /home/user/pipeline_out

    cat << 'EOF' > /home/user/data/users.csv
user_id,age,signup_source
1,25,web
2,,app
3,40,web
4,,app
5,22,web
EOF

    cat << 'EOF' > /home/user/data/events.csv
event_id,user_id,score
101,1,5.5
102,2,3.2
103,2,8.1
104,3,9.9
105,4,1.0
106,6,4.4
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/data
    chown -R user:user /home/user/pipeline_out
    chmod -R 777 /home/user
