#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq nodejs
    pip3 install pytest

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/users.jsonl
{"user_id": "u1", "department": "Engineering", "roles": ["developer", "viewer"], "access_logs": [{"doc_id": "d1", "timestamp": "2023-01-01"}, {"doc_id": "d2", "timestamp": "2023-01-02"}]}
{"user_id": "u2", "department": "Engineering", "roles": ["admin", "developer"], "access_logs": [{"doc_id": "d1", "timestamp": "2023-01-01"}]}
{"user_id": "u3", "department": "Finance", "roles": ["auditor"], "access_logs": [{"doc_id": "d3", "timestamp": "2023-01-01"}, {"doc_id": "d4", "timestamp": "2023-01-02"}, {"doc_id": "d5", "timestamp": "2023-01-03"}]}
{"user_id": "u4", "department": "Finance", "roles": ["manager", "viewer"], "access_logs": [{"doc_id": "d6", "timestamp": "2023-01-04"}]}
{"user_id": "u5", "department": "HR", "roles": ["recruiter"], "access_logs": []}
{"user_id": "u6", "department": "HR", "roles": ["recruiter", "manager"], "access_logs": [{"doc_id": "d7", "timestamp": "2023-01-05"}]}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
