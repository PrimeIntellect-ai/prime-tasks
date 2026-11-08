#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl
    pip3 install pytest

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/sensors.csv
timestamp,machine_id,temperature,vibration
T1,M1,45.0,0.12
T2,M1,46.1,0.15
T1,M2,50.2,0.50
T2,M2,51.0,0.55
T1,M3,42.1,0.05
T2,M3,42.5,0.06
T1,M4,60.0,0.80
T2,M4,61.2,0.85
T1,M5,55.0,0.60
T2,M5,56.1,0.62
T1,M6,48.0,0.20
T2,M6,49.0,0.22
EOF

    cat << 'EOF' > /home/user/data/labels.json
[
  {"timestamp": "T1", "machine_id": "M1", "wear_level": 0.1},
  {"timestamp": "T2", "machine_id": "M1", "wear_level": 0.15},
  {"timestamp": "T1", "machine_id": "M2", "wear_level": 0.6},
  {"timestamp": "T2", "machine_id": "M2", "wear_level": 0.65},
  {"timestamp": "T1", "machine_id": "M3", "wear_level": 0.02},
  {"timestamp": "T2", "machine_id": "M3", "wear_level": 0.03},
  {"timestamp": "T1", "machine_id": "M4", "wear_level": 0.9},
  {"timestamp": "T2", "machine_id": "M4", "wear_level": 0.95},
  {"timestamp": "T1", "machine_id": "M5", "wear_level": 0.7},
  {"timestamp": "T2", "machine_id": "M5", "wear_level": 0.75},
  {"timestamp": "T1", "machine_id": "M6", "wear_level": 0.2},
  {"timestamp": "T2", "machine_id": "M6", "wear_level": 0.25}
]
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
