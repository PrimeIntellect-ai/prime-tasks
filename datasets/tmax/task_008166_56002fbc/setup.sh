#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gawk coreutils
    pip3 install pytest

    mkdir -p /home/user/backups /home/user/scripts /home/user/output

    cat << 'EOF' > /home/user/backups/nodes.jsonl
{"id": "db_1", "type": "Database", "status": "ONLINE"}
{"id": "db_2", "type": "Database", "status": "OFFLINE"}
{"id": "db_3", "type": "Database", "status": "ONLINE"}
{"id": "db_4", "type": "Database", "status": "ONLINE"}
{"id": "stor_1", "type": "StorageNode", "status": "ONLINE"}
{"id": "stor_2", "type": "StorageNode", "status": "ONLINE"}
{"id": "stor_3", "type": "StorageNode", "status": "OFFLINE"}
{"id": "stor_4", "type": "StorageNode", "status": "ONLINE"}
EOF

    cat << 'EOF' > /home/user/backups/edges.csv
source_id,target_id,relation_type
stor_1,db_1,STORES_BACKUP_FOR
stor_1,db_2,STORES_BACKUP_FOR
stor_2,db_3,STORES_BACKUP_FOR
stor_3,db_1,STORES_BACKUP_FOR
db_1,app_1,DEPENDS_ON
stor_4,db_4,STORES_BACKUP_FOR
db_4,stor_4,BACKED_UP_TO
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/backups /home/user/scripts /home/user/output
    chmod -R 777 /home/user
