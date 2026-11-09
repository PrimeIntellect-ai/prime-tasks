#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_sensors.csv
timestamp,sensor_value,location_desc
100,50.5,"Tokyo, Japan
Zone A"
101,1500.0,"Invalid Zone"
103,60.5,"Paris, France"
104,-10.0,"Drop me"
105,70.5,"São Paulo, Brazil"
EOF

    chmod -R 777 /home/user
