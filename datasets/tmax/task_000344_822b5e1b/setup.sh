#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/lock_events.csv
Timestamp,Status,WaitingTxID,HoldingTxID,ResourceName
2023-10-01T10:00:01,GRANTED,5,2,RowA
2023-10-01T10:00:02,WAITING,10,20,RowB
2023-10-01T10:00:03,WAITING,20,30,RowC
2023-10-01T10:00:04,WAITING,30,10,RowD
2023-10-01T10:00:05,WAITING,40,50,RowE
2023-10-01T10:00:06,GRANTED,50,40,RowE
2023-10-01T10:00:07,WAITING,50,60,RowF
2023-10-01T10:00:08,WAITING,60,40,RowG
2023-10-01T10:00:09,WAITING,70,80,RowH
2023-10-01T10:00:10,WAITING,80,90,RowI
2023-10-01T10:00:11,WAITING,105,110,RowJ
2023-10-01T10:00:12,WAITING,110,115,RowK
2023-10-01T10:00:13,WAITING,115,105,RowL
2023-10-01T10:00:14,WAITING,200,201,RowM
2023-10-01T10:00:15,WAITING,201,200,RowN
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
