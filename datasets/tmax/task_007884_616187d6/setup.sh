#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/incoming_data

    cat << 'EOF' > /home/user/incoming_data/sensor_1.csv
timestamp,reading
1672531200,10.0
1672533000,20.0
1672536600,30.0
EOF

    cat << 'EOF' > /home/user/incoming_data/sensor_2.csv
timestamp,reading
01/01/2023 00:45:00,100.0
01/01/2023 01:15:00,150.0
01/01/2023 01:45:00,250.0
EOF

    chmod -R 777 /home/user
