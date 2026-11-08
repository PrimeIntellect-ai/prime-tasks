#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install --default-timeout=100 pytest flask fastapi uvicorn pandas

    mkdir -p /home/user/data/
    cat << 'EOF' > /home/user/data/messy_logs.csv
Timestamp,ServerID,CPU,Memory,LogLevel,Message
2023-01-01T00:00:01Z,Server-Alpha,45.5,1024,INFO,"Starting process
Process ID: 123
Success"
2023-01-01T00:00:01Z,Server-Beta,50.0,2048,WARN,"High memory
Check swap"
2023-01-01T00:00:02Z,Server-Alpha,48.0,1048,ERROR,"Crash in module
Line 42"
2023-01-01T00:00:02Z,Server-Beta,40.0,2000,INFO,"Normal operation"
2023-01-01T00:00:03Z,Server-Alpha,42.5,1030,INFO,"Restarting
ok"
2023-01-01T00:00:03Z,Server-Beta,41.0,2010,WARN,"CPU spike
temp warning"
2023-01-01T00:00:04Z,Server-Alpha,50.0,1100,ERROR,"Failed to bind
port 80"
2023-01-01T00:00:04Z,Server-Beta,42.0,2020,ERROR,"Disk full
/dev/sda1"
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
