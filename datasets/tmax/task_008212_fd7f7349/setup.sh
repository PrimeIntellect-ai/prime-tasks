#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/remote_server/archive
    mkdir -p /home/user/workspace

    cat << 'EOF' > /home/user/remote_server/raw_telemetry.csv
1001,S001,25.0,50.0,OK
1002,S002,160.0,50.0,OK
1003,A003,20.0,40.0,WARN
1004,S004,20.0,40.0,ERR
-5,S005,20.0,40.0,OK
1006,S006,30.0,60.0,WARN
1007,S123,0.0,0.0,OK
1008,S999,-50.0,100.0,WARN
1009,S01X,25.0,50.0,OK
1010,S010,25.0,105.0,OK
EOF

    chown -R user:user /home/user/remote_server
    chown -R user:user /home/user/workspace

    chmod -R 777 /home/user
