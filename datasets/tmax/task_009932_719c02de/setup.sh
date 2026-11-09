#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sensor_data.csv
100,20.00,"System Boot"
103,23.00,"Warning:
High Temp
Detected"
104,24.50,"OK"
108,22.50,"Cooling
Down"
EOF

    chmod -R 777 /home/user
