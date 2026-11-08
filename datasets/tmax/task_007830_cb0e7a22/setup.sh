#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas pyarrow

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/inputs

    cat << 'EOF' > /home/user/inputs/factory_1.csv
timestamp,Temp_A,Humidity_A
2023-10-01 10:00:00,25.4,60.1
2023-10-01 10:05:00,25.5,60.2
2023-10-01 10:10:00,25.6,60.5
EOF

    cat << 'EOF' > /home/user/inputs/factory_2.json
[
  {"time": "2023-10-01T10:00:00Z", "sensor": "TEMP_A", "reading": 25.4},
  {"time": "2023-10-01T10:05:00Z", "sensor": "Temp_C", "reading": 22.1},
  {"time": "2023-10-01 10:10:00+00:00", "sensor": "HUMIDITY_A", "reading": 60.5},
  {"time": "2023-10-01T10:15:00Z", "sensor": "Temp_C", "reading": 22.3}
]
EOF

    chmod -R 777 /home/user
