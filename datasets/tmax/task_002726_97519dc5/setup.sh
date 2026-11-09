#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os

os.makedirs('/home/user', exist_ok=True)
with open('/home/user/raw_logs.csv', 'wb') as f:
    header = "tx_id,timestamp,user_id,response_time_ms,message\n".encode('utf-8')
    f.write(header)
    f.write(b'T001,2023-10-15T14:05:10Z,U1,100,Normal operation\n')
    f.write(b'T002,2023-10-15T14:15:20Z,U2,250,"Crash! ERR-500 and \xff invalid byte"\n')
    f.write(b'T003,2023-10-15T14:32:05Z,U1,150,"User submitted \n a form with ERR-400\n and ERR-404"\n')
    f.write(b'T004,2023-10-15T14:45:00Z,U3,-50,Negative time error\n')
    f.write(b'T001,2023-10-15T14:50:00Z,U4,999,Duplicate tx_id\n')
    f.write(b'T005,2023-10-15T14:55:00Z,U3,125,Standard log ERR-500\n')
    f.write(b'T006,2023-10-15T15:02:00Z,U2,300,Timeout occurred ERR-504\n')
    f.write(b'T007,2023-10-15T15:10:00Z,U4,200,Success\n')
    f.write(b'T008,2023-10-15T15:20:00Z,U4,400,"Failed to load\nERR-504\nretry"\n')
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
