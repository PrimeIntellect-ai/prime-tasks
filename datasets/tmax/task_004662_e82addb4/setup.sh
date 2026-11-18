#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    # Create directories
    mkdir -p /app /data

    # Create dummy audit_oracle binary
    cat << 'EOF' > /app/audit_oracle
#!/bin/bash
# Dummy binary for initial state
echo '["EMP_0042", "EMP_0199"]'
EOF
    chmod +x /app/audit_oracle

    # Create initial data files
    sqlite3 /data/hr.db "CREATE TABLE employees (id TEXT, department TEXT);"
    sqlite3 /data/hr.db "INSERT INTO employees VALUES ('EMP_0042', 'Executive'), ('EMP_0199', 'Executive');"

    cat << 'EOF' > /data/access_logs.json
[
  {"emp_id": "EMP_0042", "document": "Confidential_Q4_Earnings", "timestamp": "2023-10-15T22:00:00Z"},
  {"emp_id": "EMP_0199", "document": "Confidential_Q4_Earnings", "timestamp": "2023-10-16T02:30:00Z"}
]
EOF

    cat << 'EOF' > /data/comm_graph.csv
source,target
EMP_0042,EXT_BROKER_99
EMP_0199,EXT_BROKER_99
EOF

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
