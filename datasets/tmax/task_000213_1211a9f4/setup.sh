#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cd /home/user

    # Create SQLite database
    sqlite3 graph.db <<EOF
CREATE TABLE nodes (id INTEGER PRIMARY KEY);
CREATE TABLE edges (source INTEGER, target INTEGER);

INSERT INTO nodes VALUES (1), (2), (3), (4), (5);
INSERT INTO edges VALUES (1, 2), (2, 3), (2, 4), (4, 5), (1, 4);
EOF

    # Create the buggy python script
    cat << 'EOF' > backup_graph.py
import sqlite3
import json

def run_backup():
    conn = sqlite3.connect('graph.db')
    cursor = conn.cursor()

    # BUG: Implicit cross join
    query = """
    SELECT e1.source, e1.target, e2.target
    FROM edges e1, edges e2
    """

    cursor.execute(query)
    results = cursor.fetchall()

    # Save to json
    with open('backup_paths.json', 'w') as f:
        json.dump(results, f)

if __name__ == '__main__':
    run_backup()
EOF

    chmod +x backup_graph.py
    chmod -R 777 /home/user
