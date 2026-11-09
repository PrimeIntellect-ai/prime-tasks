#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 gdb
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/service.sh
#!/bin/bash

DB="/home/user/data.db"
declare -a query_history

while true; do
    query=$(sqlite3 "$DB" "SELECT id, value, divisor FROM queries WHERE status='pending' LIMIT 1;" 2>/dev/null)

    if [ -z "$query" ]; then
        sleep 0.1
        continue
    fi

    IFS='|' read -r q_id value divisor <<< "$query"

    if [ "$divisor" -eq 0 ]; then
        sqlite3 "$DB" "UPDATE queries SET status='error' WHERE id=$q_id;"
        continue
    fi

    result=$(( value / divisor ))

    sqlite3 "$DB" "UPDATE queries SET status='done', result=$result WHERE id=$q_id;"

    query_history+=("Query $q_id computed at $(date +%s) with value $value and divisor $divisor resulting in $result")
done
EOF
    chmod +x /home/user/service.sh

    cat << 'EOF' > /home/user/fuzzer.sh
#!/bin/bash
DB="/home/user/data.db"
echo "BEGIN TRANSACTION;" > /tmp/fuzz.sql
for i in {10..2000}; do
    echo "INSERT INTO queries (id, value, divisor, status) VALUES ($i, $RANDOM, $((RANDOM % 50 + 1)), 'pending');" >> /tmp/fuzz.sql
done
echo "COMMIT;" >> /tmp/fuzz.sql
sqlite3 "$DB" < /tmp/fuzz.sql
EOF
    chmod +x /home/user/fuzzer.sh

    sqlite3 /home/user/data.db "CREATE TABLE queries (id INTEGER PRIMARY KEY, value INTEGER, divisor INTEGER, status TEXT, result INTEGER);"
    sqlite3 /home/user/data.db "INSERT INTO queries (id, value, divisor, status, result) VALUES (1, 100, 2, 'pending', NULL);"
    sqlite3 /home/user/data.db "INSERT INTO queries (id, value, divisor, status, result) VALUES (2, 50, 5, 'pending', NULL);"
    sqlite3 /home/user/data.db "INSERT INTO queries (id, value, divisor, status, result) VALUES (3, 7, 10, 'pending', NULL);"
    sqlite3 /home/user/data.db "INSERT INTO queries (id, value, divisor, status, result) VALUES (4, 200, 4, 'pending', NULL);"

    chmod -R 777 /home/user
