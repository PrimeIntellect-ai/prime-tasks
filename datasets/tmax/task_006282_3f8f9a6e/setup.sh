#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang
pip3 install pytest

mkdir -p /home/user/backup_metadata

cat << 'EOF' > /home/user/backup_metadata/b1.json
{"id": "b1", "type": "full", "parent_id": null, "size_bytes": 100, "status": "success"}
EOF

cat << 'EOF' > /home/user/backup_metadata/b2.json
{"id": "b2", "type": "incremental", "parent_id": "b1", "size_bytes": 50, "status": "success"}
EOF

cat << 'EOF' > /home/user/backup_metadata/b3.json
{"id": "b3", "type": "incremental", "parent_id": "b2", "size_bytes": 20, "status": "success"}
EOF

cat << 'EOF' > /home/user/backup_metadata/b4.json
{"id": "b4", "type": "full", "parent_id": null, "size_bytes": 200, "status": "success"}
EOF

cat << 'EOF' > /home/user/backup_metadata/b5.json
{"id": "b5", "type": "incremental", "parent_id": "b4", "size_bytes": 10, "status": "success"}
EOF

cat << 'EOF' > /home/user/backup_metadata/b6.json
{"id": "b6", "type": "incremental", "parent_id": "b5", "size_bytes": 15, "status": "failed"}
EOF

cat << 'EOF' > /home/user/backup_metadata/b7.json
{"id": "b7", "type": "incremental", "parent_id": "b6", "size_bytes": 5, "status": "success"}
EOF

cat << 'EOF' > /home/user/backup_metadata/b8.json
{"id": "b8", "type": "full", "parent_id": null, "size_bytes": 300, "status": "failed"}
EOF

cat << 'EOF' > /home/user/backup_metadata/b9.json
{"id": "b9", "type": "incremental", "parent_id": "b8", "size_bytes": 10, "status": "success"}
EOF

cat << 'EOF' > /home/user/backup_metadata/b10.json
{"id": "b10", "type": "incremental", "parent_id": "b99", "size_bytes": 10, "status": "success"}
EOF

useradd -m -s /bin/bash user || true
chown -R user:user /home/user/backup_metadata
chmod -R 777 /home/user
