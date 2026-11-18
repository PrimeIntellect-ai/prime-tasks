#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest networkx

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/backups_metadata.json
[
  {"backup_id": "f1", "type": "full", "timestamp": 1600000000, "status": "ok", "file": "s3://backups/f1.tar", "parent_id": null},
  {"backup_id": "i1", "type": "incremental", "timestamp": 1600001000, "status": "ok", "file": "s3://backups/i1.inc", "parent_id": "f1"},
  {"backup_id": "i2", "type": "incremental", "timestamp": 1600002000, "status": "ok", "file": "s3://backups/i2.inc", "parent_id": "i1"},
  {"backup_id": "d1", "type": "differential", "timestamp": 1600002000, "status": "ok", "file": "s3://backups/d1.diff", "parent_id": "f1"},
  {"backup_id": "i3", "type": "incremental", "timestamp": 1600003000, "status": "ok", "file": "s3://backups/i3.inc", "parent_id": "d1"},
  {"backup_id": "i4", "type": "incremental", "timestamp": 1600003000, "status": "ok", "file": "s3://backups/i4.inc", "parent_id": "i2"},
  {"backup_id": "i5", "type": "incremental", "timestamp": 1600003600, "status": "ok", "file": "s3://backups/i5.inc", "parent_id": "i3"},
  {"backup_id": "f2", "type": "full", "timestamp": 1600004000, "status": "ok", "file": "s3://backups/f2.tar", "parent_id": null},
  {"backup_id": "f3", "type": "full", "timestamp": 1600002500, "status": "ok", "file": "s3://backups/f3.tar", "parent_id": null},
  {"backup_id": "i6", "type": "incremental", "timestamp": 1600003000, "status": "corrupted", "file": "s3://backups/i6.inc", "parent_id": "f3"}
]
EOF

    chmod -R 777 /home/user
