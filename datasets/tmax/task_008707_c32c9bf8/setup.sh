#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/sources.csv
source_id,type
db_alpha,relational
db_beta,document
db_gamma,graph
db_delta,relational
db_epsilon,document
EOF

    cat << 'EOF' > /home/user/query_plan.json
{
  "nodes": [
    {"id": "stage_1", "source_id": "db_alpha", "time_ms": 150},
    {"id": "stage_2", "source_id": "db_beta", "time_ms": 320},
    {"id": "stage_3", "source_id": "db_gamma", "time_ms": 45},
    {"id": "stage_4", "source_id": "db_delta", "time_ms": 600},
    {"id": "stage_5", "source_id": "db_epsilon", "time_ms": 800},
    {"id": "stage_6", "source_id": "db_alpha", "time_ms": 120}
  ],
  "edges": [
    {"from": "stage_4", "to": "stage_2"},
    {"from": "stage_5", "to": "stage_3"},
    {"from": "stage_2", "to": "stage_1"},
    {"from": "stage_3", "to": "stage_1"},
    {"from": "stage_6", "to": "stage_4"}
  ]
}
EOF

    chmod -R 777 /home/user
