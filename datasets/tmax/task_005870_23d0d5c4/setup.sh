#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_pipeline_data.json
[
  {"id": "JOB_001", "name": "Extract", "compute_cost": 100, "depends_on": []},
  {"id": "JOB_002", "name": "Transform A", "compute_cost": 250, "depends_on": ["JOB_001"]},
  {"id": "JOB_003", "name": "Transform B", "compute_cost": 150, "depends_on": ["JOB_001"]},
  {"id": "JOB_004", "name": "Load A", "compute_cost": 50, "depends_on": ["JOB_002"]},
  {"id": "JOB_005", "name": "Load B", "compute_cost": 60, "depends_on": ["JOB_003"]},
  {"id": "JOB_006", "name": "Report", "compute_cost": 200, "depends_on": ["JOB_004", "JOB_005"]},
  {"id": "JOB_007", "name": "Independent Task", "compute_cost": 500, "depends_on": []},
  {"id": "JOB_008", "name": "Independent Task Followup", "compute_cost": 100, "depends_on": ["JOB_007"]}
]
EOF

    chmod -R 777 /home/user
