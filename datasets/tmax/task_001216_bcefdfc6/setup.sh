#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip make
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    BASE_DIR="/home/user/sensor_etl"
    DATA_DIR="${BASE_DIR}/data"
    OUTPUT_DIR="${BASE_DIR}/output"

    mkdir -p "${DATA_DIR}"
    mkdir -p "${OUTPUT_DIR}"

    cat << 'EOF' > "${DATA_DIR}/metadata.json"
{
    "S-01": {"baseline": 10.0},
    "S-02": {"baseline": 5.0}
}
EOF

    cat << 'EOF' > "${DATA_DIR}/calibrations.log"
[INFO] 2023-11-01T09:55:00Z - System boot sequence initiated.
[INFO] 2023-11-01T10:02:30Z - Sensor [S-01] calibrated. New multiplier: 1.10
[WARN] 2023-11-01T10:03:00Z - High latency detected.
[INFO] 2023-11-01T10:07:00Z - Sensor [S-02] calibrated. New multiplier: 0.90
EOF

    cat << 'EOF' > "${DATA_DIR}/raw_readings.csv"
timestamp,sensor_id,raw_value
2023-11-01T10:00:15Z,S-01,50.0
2023-11-01T10:00:45Z,S-02,100.0
2023-11-01T10:03:10Z,S-01,55.0
2023-11-01T10:04:05Z,S-02,110.0
2023-11-01T10:08:20Z,S-02,120.0
EOF

    chmod -R 777 /home/user
