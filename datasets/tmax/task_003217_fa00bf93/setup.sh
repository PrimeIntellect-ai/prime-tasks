#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 espeak ffmpeg
    pip3 install pytest

    mkdir -p /app

    # Create nodes.jsonl
    cat << 'EOF' > /app/nodes.jsonl
{"id": "n3", "name": "WEB_FRONTEND", "type": "server"}
{"id": "n4", "name": "STORAGE_NAS1", "type": "storage"}
{"id": "n5", "name": "CLOUD_BUCKET_B", "type": "cloud"}
EOF

    # Create sql_dump.db
    sqlite3 /app/sql_dump.db << 'EOF'
CREATE TABLE edges (src_id TEXT, dst_id TEXT);
INSERT INTO edges VALUES ('n3', 'n4');
INSERT INTO edges VALUES ('n4', 'n5');
EOF

    # Create backup_log.wav
    espeak -w /app/backup_log.wav "Critical backup routing update. The server DB_MAIN now routes backups to STORAGE_SAN1. Also, REDIS_CACHE backups are sent to STORAGE_NAS2. Ensure STORAGE_SAN1 replicates to CLOUD_BUCKET_A."

    # Setup user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
