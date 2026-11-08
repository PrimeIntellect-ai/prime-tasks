#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    mkdir -p /home/user
    cat << 'EOF' > /home/user/sensor_data.csv
s1,s2,s3,s4
2.5,1.1,5.4,0.3
3.1,1.5,4.9,0.5
2.8,1.2,5.1,0.4
3.5,1.8,4.5,0.7
2.9,1.3,5.0,0.4
3.2,1.6,4.7,0.6
2.6,1.2,5.3,0.3
3.0,1.4,4.8,0.5
EOF
    chmod 644 /home/user/sensor_data.csv

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
