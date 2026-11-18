#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/sensors.csv
sensor_id,val_x,val_y,prior_fail,p_high_given_fail,p_high_given_ok,is_high
S1,10.0,20.0,0.1,0.8,0.2,1
S2,12.0,19.0,0.2,0.9,0.1,0
S3,100.0,50.0,0.05,0.7,0.3,1
S4,15.0,22.0,0.15,0.85,0.15,1
S5,101.0,48.0,0.1,0.9,0.05,0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
