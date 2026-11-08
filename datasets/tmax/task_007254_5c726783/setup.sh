#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/backups.json
[
  {"id": "b1", "db_instance": "db-primary-1", "status": "success", "size_gb": 100},
  {"id": "b2", "db_instance": "db-replica-1", "status": "failed", "size_gb": 50},
  {"id": "b3", "db_instance": "db-replica-2", "status": "success", "size_gb": 50},
  {"id": "b4", "db_instance": "db-primary-2", "status": "success", "size_gb": 80},
  {"id": "b5", "db_instance": "db-replica-3", "status": "success", "size_gb": 80},
  {"id": "b6", "db_instance": "db-primary-3", "status": "success", "size_gb": 200},
  {"id": "b7", "db_instance": "db-replica-4", "status": "failed", "size_gb": 100},
  {"id": "b8", "db_instance": "db-replica-5", "status": "failed", "size_gb": 100},
  {"id": "b9", "db_instance": "db-replica-6", "status": "success", "size_gb": 100},
  {"id": "b10", "db_instance": "db-primary-4", "status": "failed", "size_gb": 300},
  {"id": "b11", "db_instance": "db-replica-7", "status": "success", "size_gb": 300}
]
EOF

    cat << 'EOF' > /home/user/replication_graph.csv
primary,replica
db-primary-1,db-replica-1
db-primary-1,db-replica-2
db-primary-2,db-replica-3
db-primary-3,db-replica-4
db-primary-3,db-replica-5
db-primary-3,db-replica-6
db-primary-4,db-replica-7
EOF

    chmod -R 777 /home/user
