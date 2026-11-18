#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        postgresql \
        postgresql-contrib \
        redis-server \
        curl \
        gnupg \
        sudo

    # Install MongoDB
    curl -fsSL https://pgp.mongodb.com/server-6.0.asc | gpg -o /usr/share/keyrings/mongodb-server-6.0.gpg --dearmor
    echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-6.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/6.0 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-6.0.list
    apt-get update && apt-get install -y mongodb-org

    pip3 install pytest psycopg2-binary pymongo redis python-dotenv

    mkdir -p /app
    mkdir -p /home/user/corpus/clean
    mkdir -p /home/user/corpus/evil

    # Create start_services.sh
    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
service postgresql start
sudo -u postgres psql -c "CREATE USER dbre WITH PASSWORD 'dbre_pass';" || true
sudo -u postgres psql -c "CREATE DATABASE backups OWNER dbre;" || true

mkdir -p /data/db
chown -R mongodb:mongodb /data/db
mongod --fork --logpath /var/log/mongodb.log --dbpath /data/db

redis-server --daemonize yes
EOF
    chmod +x /app/start_services.sh

    # Create query_lineage.py
    cat << 'EOF' > /app/query_lineage.py
import os
import psycopg2
from pymongo import MongoClient
import redis
from dotenv import load_dotenv

load_dotenv()

def run_pipeline():
    # Implicit cross join - needs fixing
    sql_query = "SELECT * FROM schedules s, backup_runs r"
    pass

if __name__ == "__main__":
    run_pipeline()
EOF

    # Create .env
    touch /app/.env

    # Create clean corpus
    cat << 'EOF' > /home/user/corpus/clean/valid1.json
{
    "schedule_id": "SCH-1234",
    "nodes": ["A", "B", "C"],
    "edges": [["A", "B"], ["B", "C"]],
    "metadata": {"type": "full"}
}
EOF

    # Create evil corpus
    cat << 'EOF' > /home/user/corpus/evil/evil_cycle.json
{
    "schedule_id": "SCH-1234",
    "nodes": ["A", "B"],
    "edges": [["A", "B"], ["B", "A"]],
    "metadata": {"type": "full"}
}
EOF

    cat << 'EOF' > /home/user/corpus/evil/evil_id.json
{
    "schedule_id": "BAD-1234",
    "nodes": ["A", "B"],
    "edges": [["A", "B"]],
    "metadata": {"type": "full"}
}
EOF

    cat << 'EOF' > /home/user/corpus/evil/evil_nosql.json
{
    "schedule_id": "SCH-1234",
    "nodes": ["A", "B"],
    "edges": [["A", "B"]],
    "metadata": {"$where": "sleep(1000)"}
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
