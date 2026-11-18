#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data

    sqlite3 /home/user/data/enrichment.db "CREATE TABLE users (username TEXT PRIMARY KEY, role TEXT);"
    sqlite3 /home/user/data/enrichment.db "INSERT INTO users (username, role) VALUES ('admin', 'superuser'), ('jdoe', 'analyst');"

    cat << 'EOF' > /home/user/pipeline.sh
#!/bin/bash
DB="/home/user/data/enrichment.db"
INPUT=$1
if [ ! -f "$INPUT" ]; then echo "Input file required"; exit 1; fi

rm -f /home/user/output.log
while read -r ts ip user action; do
    # VULNERABILITY/BUG: Unescaped single quotes in username break the query
    ROLE=$(sqlite3 "$DB" "SELECT role FROM users WHERE username='$user';" 2>/dev/null)

    # sqlite3 exits with 0 even if query has syntax error in some older versions, 
    # but we can force a failure check by seeing if sqlite3 outputted an error or we can 
    # just rely on set -e. Let's make it explicitly fail if the query is malformed.
    ERROR=$(sqlite3 "$DB" "SELECT role FROM users WHERE username='$user';" 2>&1 >/dev/null)
    if [[ "$ERROR" == *"Error"* || "$ERROR" == *"unrecognized"* || "$ERROR" == *"incomplete"* ]]; then
        echo "Database query failed!" >&2
        exit 1
    fi

    if [ -z "$ROLE" ]; then ROLE="UNKNOWN"; fi
    echo "$ts $ip $user $ROLE $action" >> /home/user/output.log
done < "$INPUT"
exit 0
EOF

    chmod +x /home/user/pipeline.sh

    cat << 'EOF' > /tmp/generate_logs.py
import random

users = ['admin', 'jdoe', 'bsmith', 'alice', 'bob']
actions = ['LOGIN', 'LOGOUT', 'QUERY']

with open('/home/user/data/logs.txt', 'w') as f:
    for i in range(1, 501):
        if i == 342:
            f.write("2023-10-25 192.168.1.99 O'Connor LOGIN\n")
        else:
            user = random.choice(users)
            action = random.choice(actions)
            f.write(f"2023-10-25 192.168.1.10 {user} {action}\n")
EOF
    python3 /tmp/generate_logs.py
    rm /tmp/generate_logs.py

    chmod -R 777 /home/user
