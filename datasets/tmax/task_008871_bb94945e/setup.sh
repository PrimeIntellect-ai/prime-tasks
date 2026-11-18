#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ cron
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/raw_sensor.csv
1672531200,S1,temp,20.0
1672531200,S1,temp,20.0
1672531205,S2,humidity,45.5
1672531210,S1,temp,21.0
1672531215,S1,temp,
1672531220,S1,temp,22.0
1672531230,S1,temp,20.5
1672531240,S1,temp,19.5
1672531250,S1,temp,20.0
1672531260,S1,temp,21.0
1672531270,S1,temp,22.0
1672531280,S1,temp,23.0
1672531200,S3,temp,10.0
1672531210,S3,temp,10.0
1672531220,S3,temp,10.0
1672531230,S3,temp,10.0
1672531240,S3,temp,10.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
