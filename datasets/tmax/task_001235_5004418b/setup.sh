#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/backup_metadata.json
[
  {"job_id": "job_01", "duration_minutes": 10, "depends_on": []},
  {"job_id": "job_02", "duration_minutes": 15, "depends_on": ["job_01"]},
  {"job_id": "job_03", "duration_minutes": 20, "depends_on": ["job_01"]},
  {"job_id": "job_04", "duration_minutes": 25, "depends_on": ["job_01"]},
  {"job_id": "job_05", "duration_minutes": 30, "depends_on": ["job_02", "job_03"]},
  {"job_id": "job_06", "duration_minutes": 15, "depends_on": ["job_05"]},
  {"job_id": "job_07", "duration_minutes": 40, "depends_on": ["job_05", "job_04"]},
  {"job_id": "job_08", "duration_minutes": 10, "depends_on": ["job_07"]},
  {"job_id": "job_09", "duration_minutes": 5, "depends_on": ["job_08"]},
  {"job_id": "job_10", "duration_minutes": 15, "depends_on": ["job_12"]},
  {"job_id": "job_11", "duration_minutes": 10, "depends_on": ["job_10"]},
  {"job_id": "job_12", "duration_minutes": 20, "depends_on": ["job_11"]},
  {"job_id": "job_13", "duration_minutes": 5, "depends_on": ["job_10", "job_06"]}
]
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
