#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gawk grep
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/backup_metadata.json
[
  {"backup_id": "bkp_001", "type": "full", "parent_id": null, "size_mb": 5000},
  {"backup_id": "bkp_002", "type": "incremental", "parent_id": "bkp_001", "size_mb": 1200},
  {"backup_id": "bkp_003", "type": "incremental", "parent_id": "bkp_002", "size_mb": 800},
  {"backup_id": "bkp_004", "type": "incremental", "parent_id": "bkp_001", "size_mb": 1500},
  {"backup_id": "bkp_005", "type": "incremental", "parent_id": "bkp_004", "size_mb": 300},
  {"backup_id": "bkp_006", "type": "full", "parent_id": null, "size_mb": 8000},
  {"backup_id": "bkp_007", "type": "incremental", "parent_id": "bkp_006", "size_mb": 2000},
  {"backup_id": "bkp_008", "type": "incremental", "parent_id": "bkp_007", "size_mb": 500},
  {"backup_id": "bkp_009", "type": "incremental", "parent_id": "bkp_003", "size_mb": 150}
]
EOF

    chmod -R 777 /home/user
