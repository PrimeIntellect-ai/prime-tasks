#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ nlohmann-json3-dev
    pip3 install pytest

    mkdir -p /home/user/backup_metadata

    cat << 'EOF' > /home/user/backup_metadata/servers.json
[
  {
    "server_id": "db-srv-001",
    "jobs": [
      {"job_id": "job-101", "primary_storage": "storage-A"},
      {"job_id": "job-102", "primary_storage": "storage-B"}
    ]
  },
  {
    "server_id": "db-srv-042",
    "jobs": [
      {"job_id": "job-201", "primary_storage": "storage-C"},
      {"job_id": "job-202", "primary_storage": "storage-D"}
    ]
  },
  {
    "server_id": "db-srv-089",
    "jobs": [
      {"job_id": "job-301", "primary_storage": "storage-E"}
    ]
  }
]
EOF

    cat << 'EOF' > /home/user/backup_metadata/storage_relations.csv
source_storage,replica_storage
storage-A,storage-X
storage-B,storage-X
storage-C,storage-Y
storage-C,storage-W
storage-D,storage-W
storage-Y,storage-Z
storage-Z,storage-Omega
storage-E,storage-Z
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
