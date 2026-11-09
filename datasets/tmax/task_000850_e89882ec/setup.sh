#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sqlite3 espeak
pip3 install pytest

# Create directories
mkdir -p /app/trading
mkdir -p /app/corpora/evil
mkdir -p /app/corpora/clean

# 1. Generate audio file
espeak -w /app/whistleblower.wav "Please investigate trading anomalies for employee ID E-7734 immediately."

# 2. Create SQLite database
sqlite3 /app/trading/users.db <<EOF
CREATE TABLE departments (department_id INTEGER PRIMARY KEY, department_name TEXT, risk_level INTEGER);
INSERT INTO departments VALUES (1, 'Equities', 4);
INSERT INTO departments VALUES (2, 'Fixed Income', 2);

CREATE TABLE employees (employee_id TEXT PRIMARY KEY, name TEXT, department_id INTEGER);
INSERT INTO employees VALUES ('E-7734', 'Jordan Cole', 1);
INSERT INTO employees VALUES ('E-1234', 'Alice Smith', 2);
EOF

# 3. Create JSONL execution logs
cat <<EOF > /app/trading/executions.jsonl
{"employee_id": "E-7734", "amount": 500000.00, "is_flagged": true}
{"employee_id": "E-7734", "amount": 450000.50, "is_flagged": true}
{"employee_id": "E-7734", "amount": 200000.00, "is_flagged": true}
{"employee_id": "E-7734", "amount": 300000.00, "is_flagged": false}
{"employee_id": "E-1234", "amount": 1000.00, "is_flagged": false}
EOF

# 4. Create evaluation corpora
cat <<EOF > /app/corpora/evil/payload1.json
{"filters": {"user": "admin' OR '1'='1"}}
EOF

cat <<EOF > /app/corpora/evil/payload2.json
{"filters": {"id": "1; DROP TABLE users"}}
EOF

cat <<EOF > /app/corpora/clean/payload1.json
{"filters": {"user": "admin", "status": "active"}}
EOF

cat <<EOF > /app/corpora/clean/payload2.json
{"filters": {"id": "12345"}}
EOF

# Setup user and permissions
useradd -m -s /bin/bash user || true
chmod -R 777 /app
chmod -R 777 /home/user
