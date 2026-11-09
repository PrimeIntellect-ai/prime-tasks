#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user

    cat << 'EOF' > /home/user/sensor_data.log
2023-10-12T08:00:00Z | S-101 | NA-WEST | 85.2 | 40.1
2023-10-12T08:01:00Z | S-202 | EU-CENTRAL | 89.9 | 42.0
2023-10-12T08:02:00Z | S-303 | EU-CENTRAL | 91.5 | 45.5
2023-10-12T08:03:00Z | S-404 | ASIA-EAST | 102.1 | 60.0
2023-10-12T08:04:00Z | S-505 | EU-CENTRAL | 90.1 | 41.2
2023-10-12T08:05:00Z | S-606 | EU-CENTRAL | 90.0 | 44.4
2023-10-12T08:06:00Z | S-707 | NA-EAST | 95.0 | 50.1
2023-10-12T08:07:00Z | S-808 | EU-CENTRAL | 105.3 | 39.9
EOF

    chmod 644 /home/user/sensor_data.log

    chmod -R 777 /home/user
