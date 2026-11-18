#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    mkdir -p /home/user/data
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/data/sensors.csv
sensor_id,location,is_active
101,Zone_A,true
102,Zone_B,true
103,Zone_C,false
105,Zone_D,true
EOF

    cat << 'EOF' > /home/user/data/readings.json
[
  {"reading_id": "R001", "sensor_id": 101, "value": 45.5},
  {"reading_id": "R002", "sensor_id": null, "value": 12.0},
  {"reading_id": "R003", "sensor_id": 102, "value": 42.1},
  {"reading_id": "R004", "sensor_id": 104, "value": 99.9},
  {"reading_id": "R005", "sensor_id": "101", "value": 46.0},
  {"reading_id": "R006", "sensor_id": 103, "value": 10.0},
  {"reading_id": "R007", "sensor_id": 105, "value": 8.4}
]
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
