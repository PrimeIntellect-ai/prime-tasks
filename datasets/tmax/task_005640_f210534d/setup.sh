#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ wget curl
    pip3 install pytest numpy pandas

    mkdir -p /home/user
    cat << 'EOF' > /home/user/sensor_data.csv
temp,pressure,humidity
20.5,101.3,45.2
21.0,101.5,
22.1,100.9,46.1
19.8,,44.8
100.0,101.2,45.5
20.2,101.1,45.0
21.5,101.8,47.2
,101.4,46.0
20.8,101.3,45.8
19.5,200.0,44.5
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
