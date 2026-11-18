#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc cron
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_telemetry.csv
1700000000,3.0,4.0,0.0,OK
1700001000,0.0,5.0,12.0,OK
1700002000,8.0,6.0,0.0,BROKEN
LINE
1700004000,6.0,8.0,0.0,OK
1700004500,1.0,2.0,2.0,OK
1700008000,5.0,12.0,0.0,ERR
EOF

    chmod -R 777 /home/user
