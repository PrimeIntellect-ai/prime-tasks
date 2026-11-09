#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc build-essential
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /home/user/output
    mkdir -p /home/user/etl_pipeline

    cat << 'EOF' > /home/user/data/metadata.csv
meter_id,region_id
M1,Region_A
M2,Region_A
M3,Region_B
EOF

    cat << 'EOF' > /home/user/data/readings_1.jsonl
{"timestamp": "2023-10-01T10:15:00Z", "meter_id": "M1", "reading_kw": 10.0}
{"timestamp": "2023-10-01T10:15:00Z", "meter_id": "M1", "reading_kw": 12.0}
{"timestamp": "2023-10-01T11:45:00Z", "meter_id": "M1", "reading_kw": 14.0}
{"timestamp": "2023-10-01T10:05:00Z", "meter_id": "M2", "reading_kw": 20.0}
EOF

    cat << 'EOF' > /home/user/data/readings_2.jsonl
{"timestamp": "2023-10-01T11:05:00Z", "meter_id": "M2", "reading_kw": 25.0}
{"timestamp": "2023-10-01T10:30:00Z", "meter_id": "M3", "reading_kw": 100.0}
{"timestamp": "2023-10-01T10:30:00Z", "meter_id": "M3", "reading_kw": 90.0}
{"timestamp": "2023-10-01T11:30:00Z", "meter_id": "M3", "reading_kw": 150.0}
{"timestamp": "2023-10-01T10:15:00Z", "meter_id": "M99", "reading_kw": 999.0}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
