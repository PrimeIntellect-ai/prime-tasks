#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/etl_dump.csv
timestamp,temp_sensor,humidity_sensor,pressure_sensor
1620000000,22.5,-5.0,1013.2
1620000000,22.5,-5.0,1013.2
1620000005,23.0,45.2,1012.5
1620000010,21.5,44.0,1011.0
1620000010,99.9,99.9,99.9
1620000010,21.5,44.0,1011.0
1620000015,-1.5,-2.0,1010.1
EOF

    cat << 'EOF' > /home/user/data/expected_cleaned_long.csv
timestamp,sensor_type,value
1620000000,temp,22.50
1620000000,humidity,0.00
1620000000,pressure,1013.20
1620000005,temp,23.00
1620000005,humidity,45.20
1620000005,pressure,1012.50
1620000010,temp,21.50
1620000010,humidity,44.00
1620000010,pressure,1011.00
1620000015,temp,0.00
1620000015,humidity,0.00
1620000015,pressure,1010.10
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/data
    chmod -R 777 /home/user
