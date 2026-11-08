#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential libgsl-dev sudo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/dataset.csv
sensor_count,temperature_celsius,failure_rate
5,20.5,1.2
10,22.1,2.5
,21.0,1.5
8,25.0,2.0
12,NaN,3.1
15,18.0,3.5
3,30.5,0.5
7,24.2,1.8
N/A,20.0,1.0
20,15.5,4.8
EOF

    echo "user ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

    chmod -R 777 /home/user
