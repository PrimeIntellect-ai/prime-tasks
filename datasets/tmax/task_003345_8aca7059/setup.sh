#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/raw_telemetry.csv
SN-A01,1622505600,22.5
SN-A01,1622505660,23.5
SN-A01,1622505720,24.5
XX-B02,1622505600,10.0
SN-B02,0,15.5
SN-B02,1622505660,18.0
SN-B02,1622505720,18.0
SN-C03,1622505600,160.0
SN-C03,1622505660,-55.0
SN-C03,1622505720,-10.0
SN-C03,1622505780,-20.0
SN-D04,1622505600,100.12
SN-D04,1622505660,100.18
SN-A01,1622505780,21.5
EOF

    chmod 644 /home/user/raw_telemetry.csv
    chmod -R 777 /home/user
