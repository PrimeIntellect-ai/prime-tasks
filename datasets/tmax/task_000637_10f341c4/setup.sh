#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/pipeline_repo
    cd /home/user/pipeline_repo

    git config --global user.email "test@example.com"
    git config --global user.name "Test User"
    git init

    cat << 'EOF' > init.sql
CREATE TABLE metrics (id INTEGER PRIMARY KEY, metric_name TEXT, value TEXT);
INSERT INTO metrics (metric_name, value) VALUES ('user_count', '1042');
INZERT INTO metrics (metric_name, value) VALUES ('revenue', '9984.50');
INSERT INTO metrics (metric_name, value) VALUES ('active_sessions', '342');
EOF

    cat << 'EOF' > process.sh
#!/bin/bash
TOKEN=$1

if [ -z "$TOKEN" ]; then
    echo "Error: Token required"
    exit 1
fi

rm -f data.db
sqlite3 data.db < init.sql

if [ $? -ne 0 ]; then
    echo "Database build failed"
    exit 1
# syntax error: missing fi here!

if [ "$TOKEN" == "sec_9948_aB2" ]; then
    sqlite3 data.db "SELECT metric_name, value FROM metrics WHERE metric_name='revenue';" > output.txt
else
    echo "Invalid token"
    exit 1
fi
EOF

    git add init.sql process.sh
    git commit -m "Initial commit with token"

    cat << 'EOF' > process.sh
#!/bin/bash
TOKEN=$1

if [ -z "$TOKEN" ]; then
    echo "Error: Token required"
    exit 1
fi

rm -f data.db
sqlite3 data.db < init.sql

if [ $? -ne 0 ]; then
    echo "Database build failed"
    exit 1

# TOKEN WAS REMOVED FROM BELOW
if [ "$TOKEN" == "REDACTED" ]; then
    sqlite3 data.db "SELECT metric_name, value FROM metrics WHERE metric_name='revenue';" > output.txt
else
    echo "Invalid token"
    exit 1
fi
EOF

    git add process.sh
    git commit -m "Redact hardcoded secret token for security"

    chmod +x process.sh
    chown -R user:user /home/user/pipeline_repo
    chmod -R 777 /home/user
