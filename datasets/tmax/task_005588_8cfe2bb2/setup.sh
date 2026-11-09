#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang build-essential
    pip3 install pytest

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/sales.csv
tx_id,user_id,amount,timestamp
t01,u1,10.0,2023-01-01T10:00:00Z
t02,u1,50.0,2023-01-02T10:00:00Z
t03,u1,30.0,2023-01-03T10:00:00Z
t04,u1,70.0,2023-01-04T10:00:00Z
t05,u2,20.0,2023-01-01T11:00:00Z
t06,u2,80.0,2023-01-02T11:00:00Z
t07,u2,40.0,2023-01-03T11:00:00Z
t08,u2,90.0,2023-01-04T11:00:00Z
t09,u3,100.0,2023-01-01T12:00:00Z
t10,u3,15.0,2023-01-02T12:00:00Z
t11,u3,105.0,2023-01-03T12:00:00Z
t12,u3,25.0,2023-01-04T12:00:00Z
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
