#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # 1. Create SQLite DB
    sqlite3 records.db <<EOF
CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, email TEXT, alias_id INTEGER);
INSERT INTO users (id, name, email, alias_id) VALUES (1, 'Alice', 'alice@example.com', NULL);
INSERT INTO users (id, name, email, alias_id) VALUES (2, 'Bob', 'bob@example.com', NULL);
INSERT INTO users (id, name, email, alias_id) VALUES (3, 'Charlie', 'charlie@example.com', NULL);
INSERT INTO users (id, name, email, alias_id) VALUES (10, 'Dave', 'dave@example.com', 11);
INSERT INTO users (id, name, email, alias_id) VALUES (11, 'Eve', 'eve@example.com', 10);
EOF

    # 2. Create input_ids.txt
    cat <<EOF > input_ids.txt
1
2
10
ERR_CORRUPT_882A
3
EOF

    # 3. Create export_tool.py
    cat <<EOF > export_tool.py
import sys
import sqlite3
import json

def resolve_alias(db_cursor, user_id):
    current_id = user_id
    while True:
        db_cursor.execute("SELECT alias_id FROM users WHERE id = ?", (current_id,))
        row = db_cursor.fetchone()
        if row and row[0] is not None:
            current_id = row[0]
        else:
            break
    return current_id

def process_ids(filename, db_path):
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    results = []

    with open(filename, 'r') as f:
        for line in f:
            line = line.strip()
            if not line: continue

            # Flawed input handling loop
            valid_id = False
            uid = None
            while not valid_id:
                try:
                    uid = int(line)
                    valid_id = True
                except ValueError:
                    # Infinite loop on corrupted data
                    continue

            if valid_id and uid is not None:
                real_id = resolve_alias(cursor, uid)
                cursor.execute("SELECT name, email FROM users WHERE id = ?", (real_id,))
                user_data = cursor.fetchone()
                if user_data:
                    results.append({"id": uid, "real_id": real_id, "name": user_data[0], "email": user_data[1]})

    with open('/home/user/export_results.json', 'w') as out:
        json.dump(results, out, indent=2)

if __name__ == '__main__':
    if len(sys.argv) != 3:
        print("Usage: python export_tool.py <input_file> <db_file>")
        sys.exit(1)
    process_ids(sys.argv[1], sys.argv[2])
EOF

    # 4. Create wrapper script
    cat <<EOF > run_export.sh
#!/bin/bash
python3 /home/user/export_tool.py /home/user/input_ids.txt /home/user/records.db
EOF
    chmod +x run_export.sh export_tool.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
