#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/pipeline_logs.jsonl
{"timestamp": "2023-10-01T10:00:00", "job_id": "job_001", "status": "STARTED", "records_processed": 0}
{"timestamp": "2023-10-01T10:05:00", "job_id": "job_001", "status": "SUCCESS", "records_processed": 100}
{"timestamp": "2023-10-01T10:10:00", "job_id": "job_002", "status": "STARTED", "records_processed": 0}
{"timestamp": "2023-10-01T10:12:00", "job_id": "job_002", "status": "FAILED", "records_processed": 45}
{"timestamp": "2023-10-01T10:15:00", "job_id": "job_002", "status": "RETRYING", "records_processed": 0}
{"timestamp": "2023-10-01T10:25:00", "job_id": "job_002", "status": "SUCCESS", "records_processed": 100}
{"timestamp": "2023-10-01T10:30:00", "job_id": "job_003", "status": "STARTED", "records_processed": 0}
{"timestamp": "2023-10-01T10:35:00", "job_id": "job_003", "status": "SUCCESS", "records_processed": 50}
{"timestamp": "2023-10-01T10:40:00", "job_id": "job_004", "status": "STARTED", "records_processed": 0}
{"timestamp": "2023-10-01T10:45:00", "job_id": "job_004", "status": "FAILED", "records_processed": 80}
{"timestamp": "2023-10-01T10:50:00", "job_id": "job_004", "status": "RETRYING", "records_processed": 0}
{"timestamp": "2023-10-01T11:00:00", "job_id": "job_004", "status": "SUCCESS", "records_processed": 150}
EOF

    cat << 'EOF' > /home/user/generate_csv.py
import csv

with open('/home/user/data/output_data.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['record_id', 'job_id', 'data_payload'])

    # job_001
    for i in range(10):
        writer.writerow([f'rec_1_{i}', 'job_001', 'data'])

    # job_002
    for i in range(45):
        writer.writerow([f'rec_2_{i}', 'job_002', 'data'])
    for i in range(100):
        writer.writerow([f'rec_2_{i}', 'job_002', 'data'])

    # job_003
    for i in range(50):
        writer.writerow([f'rec_3_{i}', 'job_003', 'data'])

    # job_004
    for i in range(80):
        writer.writerow([f'rec_4_{i}', 'job_004', 'data'])
    for i in range(150):
        writer.writerow([f'rec_4_{i}', 'job_004', 'data'])
EOF
    python3 /home/user/generate_csv.py
    rm /home/user/generate_csv.py

    chmod -R 777 /home/user
