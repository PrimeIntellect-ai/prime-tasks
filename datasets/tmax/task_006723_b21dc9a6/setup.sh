#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sqlite3
pip3 install pytest

useradd -m -s /bin/bash user || true

sqlite3 /home/user/users.db <<EOF
CREATE TABLE users (id INTEGER PRIMARY KEY, username TEXT, role TEXT);
INSERT INTO users (username, role) VALUES ('alice', 'admin');
INSERT INTO users (username, role) VALUES ('bob', 'user');
INSERT INTO users (username, role) VALUES ("O'Connor", 'guest');
INSERT INTO users (username, role) VALUES ('dave_ops', 'devops');
EOF

cat << 'EOF' > /home/user/log_processor.py
import os
import sqlite3
import threading
import time
import json

role_counts = {}

def process_log_file(file_path, db_path):
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    with open(file_path, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue

            # Log format: [TIMESTAMP] USERNAME ACTION
            parts = line.split(' ')
            if len(parts) >= 3:
                username = parts[1]

                # BUG 1: Vulnerable / Buggy string interpolation
                query = f"SELECT role FROM users WHERE username = '{username}'"
                try:
                    cursor.execute(query)
                    result = cursor.fetchone()
                    role = result[0] if result else 'unknown'
                except Exception as e:
                    print(f"Error processing {username}: {e}")
                    continue

                # BUG 2: Race condition
                current_count = role_counts.get(role, 0)
                time.sleep(0.001) # Exacerbate race condition
                role_counts[role] = current_count + 1

    conn.close()

def main(log_dir, db_path):
    global role_counts
    role_counts.clear()

    threads = []
    for filename in os.listdir(log_dir):
        if filename.endswith('.log'):
            file_path = os.path.join(log_dir, filename)
            t = threading.Thread(target=process_log_file, args=(file_path, db_path))
            threads.append(t)
            t.start()

    for t in threads:
        t.join()

    return role_counts

if __name__ == "__main__":
    counts = main("/home/user/test_logs", "/home/user/users.db")
    print(json.dumps(counts))
EOF

mkdir -p /home/user/test_logs

cat << 'EOF' > /home/user/test_logs/app_1.log
[2023-10-01T10:00:00] alice LOGIN
[2023-10-01T10:00:01] bob VIEW
[2023-10-01T10:00:02] O'Connor VIEW
[2023-10-01T10:00:03] bob LOGOUT
EOF

cat << 'EOF' > /home/user/test_logs/app_2.log
[2023-10-01T10:00:04] alice VIEW
[2023-10-01T10:00:05] dave_ops DEPLOY
[2023-10-01T10:00:06] alice LOGOUT
[2023-10-01T10:00:07] O'Connor LOGOUT
EOF

cat << 'EOF' > /home/user/test_logs/app_3.log
[2023-10-01T10:00:08] bob LOGIN
[2023-10-01T10:00:09] bob VIEW
[2023-10-01T10:00:10] O'Connor LOGIN
[2023-10-01T10:00:11] dave_ops LOGOUT
EOF

chmod -R 777 /home/user
