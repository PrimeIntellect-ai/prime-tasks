#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sqlite3
pip3 install pytest

mkdir -p /home/user
cd /home/user

# Create SQLite DB
sqlite3 backups.db <<EOF
CREATE TABLE backup_lineage (id INTEGER PRIMARY KEY, parent_id INTEGER, type TEXT, size INTEGER);
INSERT INTO backup_lineage VALUES (1, NULL, 'full', 1000);
INSERT INTO backup_lineage VALUES (2, 1, 'incremental', 100);
INSERT INTO backup_lineage VALUES (3, 2, 'incremental', 50);
INSERT INTO backup_lineage VALUES (4, 1, 'incremental', 120);
INSERT INTO backup_lineage VALUES (5, NULL, 'full', 2000);
INSERT INTO backup_lineage VALUES (6, 5, 'incremental', 200);
EOF

# Create buggy Python script
cat << 'EOF' > /home/user/export_lineage.py
import sqlite3
import sys
import json

def export_lineage(backup_id):
    conn = sqlite3.connect('/home/user/backups.db')
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()

    # TODO: Create index 'idx_parent' on parent_id here

    # Buggy recursive query
    query = """
    WITH RECURSIVE lineage AS (
        SELECT id, parent_id, type, size FROM backup_lineage WHERE id = ?
        UNION ALL
        SELECT b.id, b.parent_id, b.type, b.size
        FROM backup_lineage b, lineage l
        WHERE b.type = l.type AND b.parent_id IS NOT NULL LIMIT 100
    )
    SELECT * FROM lineage;
    """

    cursor.execute(query, (backup_id,))
    rows = cursor.fetchall()

    result = [dict(row) for row in rows]
    print(json.dumps(result, indent=2))

if __name__ == "__main__":
    if len(sys.argv) > 1:
        export_lineage(int(sys.argv[1]))
EOF

chmod +x /home/user/export_lineage.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
