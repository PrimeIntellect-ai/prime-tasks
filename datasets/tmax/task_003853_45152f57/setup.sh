#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip make
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/raw_logs.csv
timestamp,session_id,response_time,message
2023-10-01T10:00:00Z,S1,150,"Starting process
Initializing..."
2023-10-01T10:00:15Z,S1,300,"Slow operation completed"
2023-10-01T10:00:05Z,S1,200,"Error encountered:
Traceback (most recent call last):
  File 'app.py', line 10
ValueError: bad data"
2023-10-01T10:00:10Z,S1,100,"Recovered from error"
2023-10-01T10:00:02Z,S2,50,"Init S2"
2023-10-01T10:00:06Z,S2,60,"Process S2"
2023-10-01T10:00:01Z,,400,"Ghost log"
2023-10-01T10:00:08Z,S2,100,"End S2
Success."
2023-10-01T10:00:12Z,S2,20,"Cleanup S2"
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
