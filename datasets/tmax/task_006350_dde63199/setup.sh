#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sensor_logs.csv
tx_id,timestamp_ms,sensor_type,value,unit
tx01,1625000001,TEMP,77.0,F
tx02,1625000499,TEMP,25.0,C
tx03,1625001500,PRESSURE,10.0,PSI
tx04,1625001600,PRESSURE,68.95,kPa
tx05,1625003000,TEMP,invalid,C
tx06,1625004000,UNKNOWN,10,X
tx07,1625005000,TEMP,20.0,C
EOF

    chmod -R 777 /home/user
