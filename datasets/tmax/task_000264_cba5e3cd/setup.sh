#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/etl.log
2023-10-01T10:00:00 JOB_A START
2023-10-01T10:05:00 JOB_A SUCCESS
2023-10-01T10:10:00 JOB_B START
2023-10-01T10:12:00 JOB_B ERROR
2023-10-01T10:13:00 JOB_B RETRY
2023-10-01T10:15:00 JOB_B SUCCESS
2023-10-01T10:20:00 JOB_C START
2023-10-01T10:25:00 JOB_C SUCCESS
2023-10-01T10:30:00 JOB_D START
2023-10-01T10:32:00 JOB_D RETRY
2023-10-01T10:35:00 JOB_D SUCCESS
EOF

    cat << 'EOF' > /home/user/events.csv
job_id,txn_id,amount
JOB_A,TXN_001,150
JOB_B,TXN_002,50
JOB_B,TXN_003,200
JOB_B,TXN_003,200
JOB_C,TXN_004,300
JOB_D,TXN_005,500
JOB_D,TXN_006,99
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
