#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    mkdir -p /home/user/data
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/data/users.csv
user_id,signup_date,country,tier
1,2023-01-01,US,free
2,2023-01-02,CA,premium
3,2023-01-03,US,premium
4,2023-01-04,UK,free
EOF

    cat << 'EOF' > /home/user/data/activity.csv
timestamp,user_id,action,duration
2023-10-01T10:00:00Z,1,login,5
2023-10-01T10:05:00Z,1,view,10
2023-10-01T11:00:00Z,2,login,5
2023-10-01T11:15:00Z,2,view,-5
2023-10-01T12:00:00Z,3,,10
2023-10-02T10:00:00Z,4,login,5
2023-10-02T10:05:00Z,5,view,10
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
