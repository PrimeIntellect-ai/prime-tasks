#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar gzip jq gawk coreutils
    pip3 install pytest

    mkdir -p /home/user/data/measurements
    cd /home/user/data/measurements

    cat << 'EOF' > station_A.json
[
  {"timestamp": "2023-08-01T12:00:00Z", "station_id": "ST-A1", "temperature": 38.5, "humidity": 45},
  {"timestamp": "2023-08-02T12:00:00Z", "station_id": "ST-A1", "temperature": 41.2, "humidity": 42},
  {"timestamp": "2023-08-03T12:00:00Z", "station_id": "ST-A2", "temperature": 40.0, "humidity": 40}
]
EOF

    cat << 'EOF' > station_B.json
[
  {"timestamp": "2023-08-01T12:00:00Z", "station_id": "ST-B1", "temperature": 42.5, "humidity": 30},
  {"timestamp": "2023-08-02T12:00:00Z", "station_id": "ST-B1", "temperature": 39.9, "humidity": 35}
]
EOF

    cat << 'EOF' > station_C.csv
timestamp,station_id,temperature,humidity
2023-08-01T12:00:00Z,ST-C1,39.0,50
2023-08-02T12:00:00Z,ST-C1,45.1,48
2023-08-03T12:00:00Z,ST-C2,40.5,49
EOF

    cat << 'EOF' > station_D.csv
timestamp,station_id,temperature,humidity
2023-08-01T12:00:00Z,ST-A1,43.0,40
2023-08-02T12:00:00Z,ST-D1,37.0,55
EOF

    cd /home/user/data
    tar -czf raw_measurements.tar.gz measurements/
    rm -rf measurements/

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
