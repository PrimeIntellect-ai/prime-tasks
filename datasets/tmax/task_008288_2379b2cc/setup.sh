#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip libsqlite3-dev libjson-c-dev gcc sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/datasets.jsonl
{"id": 1, "parent_id": null, "name": "Science", "size": 0}
{"id": 2, "parent_id": 1, "name": "Physics", "size": 100}
{"id": 3, "parent_id": 1, "name": "Biology", "size": 200}
{"id": 4, "parent_id": 2, "name": "Astrophysics", "size": 50}
{"id": 5, "parent_id": 4, "name": "Stellar Dynamics", "size": 500}
{"id": 6, "parent_id": 4, "name": "Cosmology", "size": 300}
{"id": 7, "parent_id": 6, "name": "Dark Matter", "size": 150}
{"id": 8, "parent_id": 3, "name": "Genetics", "size": 400}
EOF

    chmod -R 777 /home/user
