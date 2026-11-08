#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest pandas numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_sensors.csv
Timestamp,R1_Temp,R1_Hum,R2_Temp,R2_Hum
1000,22.0,45.0,23.5,42.0
1060,22.1,45.2,23.6,42.1
1120,22.5,45.1,23.7,42.0
1180,28.0,46.0,23.6,42.2
1240,22.2,45.5,23.8,42.1
EOF

    chmod -R 777 /home/user
