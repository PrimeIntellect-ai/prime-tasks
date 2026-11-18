#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest

    mkdir -p /home/user/backups

    cat << 'EOF' > /home/user/backups/A1.json
{"id": "A1", "type": "full", "timestamp": 1000, "file": "backup_A1.tar.gz", "parent_id": null}
EOF

    cat << 'EOF' > /home/user/backups/A2.json
{"id": "A2", "type": "incremental", "timestamp": 1010, "file": "backup_A2.tar.gz", "parent_id": "A1"}
EOF

    cat << 'EOF' > /home/user/backups/A3.json
{"id": "A3", "type": "incremental", "timestamp": 1020, "file": "backup_A3.tar.gz", "parent_id": "A2"}
EOF

    cat << 'EOF' > /home/user/backups/B1.json
{"id": "B1", "type": "full", "timestamp": 2000, "file": "backup_B1.tar.gz", "parent_id": null}
EOF

    cat << 'EOF' > /home/user/backups/B2.json
{"id": "B2", "type": "incremental", "timestamp": 2010, "file": "backup_B2.tar.gz", "parent_id": "B1"}
EOF

    cat << 'EOF' > /home/user/backups/B3.json
{"id": "B3", "type": "incremental", "timestamp": 2020, "file": "backup_B3.tar.gz", "parent_id": "B2"}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/backups
    chmod -R 777 /home/user
