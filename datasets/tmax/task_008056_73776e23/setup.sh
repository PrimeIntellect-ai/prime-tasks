#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gnupg curl procps

    # Install MongoDB for Ubuntu 22.04
    curl -fsSL https://www.mongodb.org/static/pgp/server-6.0.asc | gpg --dearmor -o /usr/share/keyrings/mongodb-server-6.0.gpg
    echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-6.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/6.0 multiverse" > /etc/apt/sources.list.d/mongodb-org-6.0.list
    apt-get update
    apt-get install -y mongodb-org

    pip3 install pytest pymongo networkx

    # Create MongoDB data directory
    mkdir -p /data/db

    # Start MongoDB in the background to populate the database
    mongod --fork --logpath /var/log/mongodb.log --bind_ip_all
    sleep 3

    # Populate the database
    cat << 'EOF' > /tmp/setup_db.py
from pymongo import MongoClient

client = MongoClient('localhost', 27017)
db = client.compliance
collection = db.access_logs

logs = [
    # Irrelevant resource
    {"event_id": "1", "action": "GRANT", "actor": "contractor_01", "target": "dev_01", "resource": "wiki"},

    # Target resource: vault_prod
    {"event_id": "2", "action": "GRANT", "actor": "contractor_01", "target": "emp_02", "resource": "vault_prod"},
    {"event_id": "3", "action": "GRANT", "actor": "emp_02", "target": "emp_05", "resource": "vault_prod"},
    {"event_id": "4", "action": "GRANT", "actor": "emp_05", "target": "admin_01", "resource": "vault_prod"},
    {"event_id": "5", "action": "GRANT", "actor": "contractor_01", "target": "emp_03", "resource": "vault_prod"},

    # Disconnected graph for vault_prod
    {"event_id": "6", "action": "GRANT", "actor": "ceo", "target": "cfo", "resource": "vault_prod"},

    # Cycle to test graph traversal
    {"event_id": "7", "action": "GRANT", "actor": "admin_01", "target": "emp_02", "resource": "vault_prod"},

    # Other actions
    {"event_id": "8", "action": "REVOKE", "actor": "admin_01", "target": "emp_03", "resource": "vault_prod"},
]

collection.insert_many(logs)
EOF
    python3 /tmp/setup_db.py

    # Shutdown MongoDB
    mongod --shutdown

    # Create a script to ensure MongoDB is running when the container is executed
    cat << 'EOF' > /.singularity.d/env/99-start-mongo.sh
#!/bin/sh
if ! pgrep -x "mongod" > /dev/null; then
    mongod --fork --logpath /var/log/mongodb.log --bind_ip_all > /dev/null 2>&1 || true
fi
EOF
    chmod +x /.singularity.d/env/99-start-mongo.sh

    # Create the user
    useradd -m -s /bin/bash user || true

    # Set permissions
    chmod -R 777 /home/user
    chmod -R 777 /data/db
    chmod 777 /var/log/mongodb.log || true
