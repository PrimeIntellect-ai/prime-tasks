#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest networkx jsonschema

    mkdir -p /home/user/data /home/user/output

    cat << 'EOF' > /home/user/data/employees.jsonl
{"emp_id": "E1", "name": "Alice", "manager_id": "E3", "skills": ["python", "bash"]}
{"emp_id": "E2", "name": "Bob", "manager_id": "E3", "skills": ["java", "sql"]}
{"emp_id": "E3", "name": "Charlie", "manager_id": null, "skills": ["agile", "python"]}
{"emp_id": "E4", "name": "Diana", "manager_id": "E5", "skills": ["c++"]}
{"emp_id": "E5", "name": "Eve", "manager_id": null, "skills": ["management"]}
{"emp_id": "E6", "name": "Frank", "manager_id": "E1", "skills": ["ruby", "bash"]}
EOF

    cat << 'EOF' > /home/user/data/projects.jsonl
{"proj_id": "P1", "name": "BackendRewrite", "members": ["E1", "E2"]}
{"proj_id": "P2", "name": "LegacyMaintain", "members": ["E4"]}
{"proj_id": "P3", "name": "InternalTools", "members": ["E6"]}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
