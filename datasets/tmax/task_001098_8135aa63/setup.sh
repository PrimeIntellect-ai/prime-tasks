#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/pipeline
    cd /home/user/pipeline

    cat << 'EOF' > build.sh
#!/bin/bash

echo "Building database..."
rm -f db.sqlite
sqlite3 db.sqlite < schema.sql

# Import data
sqlite3 -csv db.sqlite ".import data.csv users"

echo "Running parser..."
python3 parser.py
EOF
    chmod +x build.sh

    cat << 'EOF' > schema.sql
CREATE TABLE users (
    id INTEGER PRIMARY KEY,
    username TEXT,
    status TEXT
);
EOF

    cat << 'EOF' > data.csv
id,username,status
1,alice,active
2,bob,inactive
3,charlie,active
4,dave,active
EOF

    cat << 'EOF' > data.log
INFO|alice|Login successful
INFO|bob|Login failed
ERROR|charlie|Database error|Timeout occurred
INFO|alice|Logout
EOF

    cat << 'EOF' > parser.py
import sqlite3
import sys

def parse_logs(log_file):
    users_seen = set()
    with open(log_file, 'r') as f:
        for line in f:
            if not line.strip(): continue
            level, user, msg = line.strip().split('|')
            users_seen.add(user)
    return users_seen

def check_users(db_file, users):
    conn = sqlite3.connect(db_file)
    cur = conn.cursor()
    active_users = []
    for user in users:
        cur.execute("SELECT username FROM users WHERE username = ? AND status = 'ACTIVE'", (user,))
        row = cur.fetchone()
        if row:
            active_users.append(row[0])
    return active_users

def main():
    users = parse_logs('data.log')
    active = check_users('db.sqlite', users)

    with open('report.txt', 'w') as f:
        f.write(f"Active users seen in logs: {','.join(sorted(active))}\n")
    print("Report generated successfully.")

if __name__ == '__main__':
    main()
EOF

    chown -R user:user /home/user/pipeline
    chmod -R 777 /home/user
