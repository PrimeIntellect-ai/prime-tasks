#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sensor_data.csv
s1,100,2
s2,-5,1
s3,50,55
s4,200,10
s5,foo,bar
s6,50,0
s7,100,100
s8,0,0
s9,150,-2
s10,300,15
EOF

    chmod -R 777 /home/user
