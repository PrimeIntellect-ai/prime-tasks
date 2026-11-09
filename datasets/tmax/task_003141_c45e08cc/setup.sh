#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    mkdir -p /home/user/data

    # Create File A (UTF-16LE)
    cat << 'EOF' > /tmp/sensor_a_utf8.csv
time,device,value,status
101,TX1,10,OK
102,TX1,14,OK
103,TX2,20,HOT_°C
EOF
    iconv -f UTF-8 -t UTF-16LE /tmp/sensor_a_utf8.csv > /home/user/data/sensor_a.csv

    # Create File B (ISO-8859-1)
    cat << 'EOF' > /tmp/sensor_b_utf8.csv
time,device,value,status
104,TX1,10,OK
105,TX1,15,OK
106,TX1,19,HOT_°C
107,TX2,20,HOT_°C
EOF
    iconv -f UTF-8 -t ISO-8859-1 /tmp/sensor_b_utf8.csv > /home/user/data/sensor_b.csv

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
