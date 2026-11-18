#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/nodes.json
[
  {"id": "db1", "label": "Database", "properties": {"name": "prod-db-1"}},
  {"id": "db2", "label": "Database", "properties": {"name": "prod-db-2"}},
  {"id": "job1", "label": "BackupJob", "properties": {"status": "FAILED", "timestamp": "2023-10-01T12:00:00Z"}},
  {"id": "job2", "label": "BackupJob", "properties": {"status": "SUCCESS"}},
  {"id": "job3", "label": "BackupJob", "properties": {"status": "FAILED", "timestamp": "invalid-time"}},
  {"id": "job4", "label": "BackupJob", "properties": {"status": "FAILED", "timestamp": "2023-10-02T12:00:00Z"}},
  {"id": "s1", "label": "StorageNode", "properties": {"type": "S3", "bucket": "backup-bucket"}},
  {"id": "s2", "label": "StorageNode", "properties": {"type": "NFS", "path": "/mnt/backups"}}
]
EOF

    cat << 'EOF' > /home/user/edges.json
[
  {"source": "db1", "target": "job1", "type": "HAS_BACKUP"},
  {"source": "job1", "target": "s1", "type": "STORED_ON"},
  {"source": "db2", "target": "job2", "type": "HAS_BACKUP"},
  {"source": "job2", "target": "s2", "type": "STORED_ON"},
  {"source": "db1", "target": "job3", "type": "HAS_BACKUP"},
  {"source": "job3", "target": "s1", "type": "STORED_ON"},
  {"source": "db2", "target": "job4", "type": "HAS_BACKUP"},
  {"source": "job4", "target": "s2", "type": "STORED_ON"}
]
EOF

    chmod -R 777 /home/user
