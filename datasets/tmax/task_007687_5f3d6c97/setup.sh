#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

mkdir -p /home/user/data_source
mkdir -p /home/user/backups

cat << 'EOF' > /home/user/backup_config.yaml
archive_name: "/home/user/backups/sanitized_backup.tar.gz"
source_directory: "/home/user/data_source"
anonymize_logs: true
include_db: true
EOF

cat << 'EOF' > /home/user/data_source/access.log
192.168.1.100 GET /index.html 200
10.0.0.5 POST /api/data 500
255.255.255.255 GET /health 200
EOF

cat << 'EOF' > /home/user/data_source/app.log
[INFO] Server started at 172.16.0.2
[ERROR] Database connection failed from 127.0.0.1
EOF

cat << 'EOF' > /home/user/data_source/dump.sql
INSERT INTO users (id, name) VALUES (1, 'admin');
INSERT INTO logs (ip) VALUES ('192.168.1.1');
EOF

cat << 'EOF' > /home/user/data_source/ignore.txt
This file should not be archived or it doesn't matter, but it doesn't match .log or .sql. Actually, the prompt says "If anonymize_logs is true, any file ending with .log must have all IPv4 addresses... If include_db is true, files ending in .sql should be included". It doesn't explicitly exclude other files, but usually they are ignored or included. Let's just stick to .log and .sql in the test.
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
