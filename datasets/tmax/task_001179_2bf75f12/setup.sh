#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ nlohmann-json3-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_metrics.csv
ts,hostname,cpu,mem,disk,event_log
1700000000,serverA,10.5,1024.0,50.0,Normal startup
1700000060,serverA,11.0,1030.0,55.0,"Update applied
Restarting agents"
1700000060,serverA,11.0,1030.0,55.0,"Update applied
Restarting agents"
1700000120,serverA,45.0,1050.0,60.0,Running smoothly
1700000180,serverA,140.0,3200.0,200.0,"Spike detected
High CPU load
Investigate immediately"
1700000180,serverB,20.0,2048.0,100.0,Normal startup
1700000240,serverB,22.0,2050.0,105.0,OK
EOF

    chmod -R 777 /home/user
