#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/dataset /home/user/backup

    cat << 'EOF' > /home/user/dataset/criteria.ini
[Filters]
valid_sensors = Temperature, Humidity, Radiation
min_value = 10.5
EOF

    cat << 'EOF' > /home/user/dataset/instrument.log
---
RecordID: 101
Date: 2023-11-01
SensorType: Temperature
Value: 15.2
---
RecordID: 102
Date: 2023-11-01
SensorType: Pressure
Value: 101.3
---
RecordID: 103
Date: 2023-11-02
SensorType: Humidity
Value: 45.0
---
RecordID: 104
Date: 2023-11-02
SensorType: Temperature
Value: 8.5
---
RecordID: 105
Date: 2023-11-03
SensorType: Radiation
Value: 12.1
---
RecordID: 106
Date: 2023-11-03
SensorType: Temperature
Value: 22.4
EOF

    cat << 'EOF' > /home/user/backup/archive.jsonl
{"RecordID": "101", "Date": "2023-11-01", "SensorType": "Temperature", "Value": 15.2}
{"RecordID": "099", "Date": "2023-10-31", "SensorType": "Humidity", "Value": 50.1}
EOF

    chmod -R 777 /home/user
