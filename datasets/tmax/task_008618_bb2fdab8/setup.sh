#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/time_series_in

    cat << 'EOF' > /home/user/time_series_in/batch_alpha.csv
timestamp,sensor_id,value,etl_run_id
2023-10-01T10:00:00Z,S1,10.0,1
2023-10-01T12:00:00Z,S1,20.0,1
2023-10-01T10:00:00Z,S1,12.0,2
2023-10-01T11:00:00Z,S2,15.0,1
2023-10-02T09:00:00Z,S1,8.0,1
2023-10-02T09:00:00Z,S1,7.0,2
EOF

    cat << 'EOF' > /home/user/time_series_in/batch_beta.jsonl
{"timestamp": "2023-10-01T12:00:00Z", "sensor_id": "S1", "value": 22.0, "etl_run_id": 2}
{"timestamp": "2023-10-01T10:00:00Z", "sensor_id": "S1", "value": 9.0, "etl_run_id": 3}
{"timestamp": "2023-10-02T09:00:00Z", "sensor_id": "S1", "value": 8.5, "etl_run_id": 3}
{"timestamp": "2023-10-02T10:00:00Z", "sensor_id": "S2", "value": 20.0, "etl_run_id": 1}
{"timestamp": "2023-10-02T10:00:00Z", "sensor_id": "S2", "value": 21.5, "etl_run_id": 2}
{"timestamp": "2023-10-03T01:00:00Z", "sensor_id": "S3", "value": 100.123, "etl_run_id": 1}
{"timestamp": "2023-10-03T01:00:00Z", "sensor_id": "S3", "value": 100.456, "etl_run_id": 2}
EOF

    chmod -R 777 /home/user
