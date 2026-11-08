#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl gnupg sudo
    pip3 install pytest psycopg2-binary pymongo

    # Install MongoDB 6.0 and PostgreSQL
    curl -fsSL https://pgp.mongodb.com/server-6.0.asc | gpg -o /usr/share/keyrings/mongodb-server-6.0.gpg --dearmor
    echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-6.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/6.0 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-6.0.list
    apt-get update
    apt-get install -y mongodb-org postgresql postgresql-contrib

    mkdir -p /app
    mkdir -p /data/db

    cat << 'EOF' > /app/populate.py
import psycopg2
from pymongo import MongoClient
import uuid

conn = psycopg2.connect(host='localhost', user='postgres', password='postgres', dbname='backups')
cur = conn.cursor()

cur.execute("""
CREATE TABLE jobs (id SERIAL PRIMARY KEY);
CREATE TABLE nodes (
    id SERIAL PRIMARY KEY,
    job_id INT,
    parent_id INT,
    name VARCHAR(255),
    type VARCHAR(50),
    file_id VARCHAR(255)
);
""")

client = MongoClient('mongodb://localhost:27017/')
db = client.backups

for job_id in range(1, 51):
    cur.execute("INSERT INTO jobs (id) VALUES (%s)", (job_id,))
    cur.execute("INSERT INTO nodes (job_id, parent_id, name, type, file_id) VALUES (%s, NULL, 'root', 'dir', NULL) RETURNING id", (job_id,))
    root_id = cur.fetchone()[0]

    for i in range(3):
        file_id = str(uuid.uuid4())
        cur.execute("INSERT INTO nodes (job_id, parent_id, name, type, file_id) VALUES (%s, %s, %s, 'file', %s)", 
                    (job_id, root_id, f"file_{i}.txt", file_id))

        for j in range(2):
            db.chunks.insert_one({
                'file_id': file_id,
                'chunk_index': j,
                'data': f"data_{job_id}_{i}_{j}\n"
            })

conn.commit()
EOF

    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
service postgresql start
mongod --fork --logpath /var/log/mongodb.log --dbpath /data/db
sleep 5
sudo -u postgres psql -c "ALTER USER postgres PASSWORD 'postgres';"
sudo -u postgres psql -c "CREATE DATABASE backups;"
python3 /app/populate.py
EOF
    chmod +x /app/start_services.sh

    cat << 'EOF' > /app/oracle_restore_tool
#!/usr/bin/env python3
import sys
import json
import argparse
import psycopg2
from pymongo import MongoClient

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--job-id', type=int, required=True)
    args = parser.parse_args()

    conn = psycopg2.connect(host='localhost', user='postgres', password='postgres', dbname='backups')
    cur = conn.cursor()

    cur.execute("""
    WITH RECURSIVE tree AS (
        SELECT id, parent_id, name, type, file_id, name::text as path
        FROM nodes
        WHERE job_id = %s AND parent_id IS NULL
        UNION ALL
        SELECT n.id, n.parent_id, n.name, n.type, n.file_id, t.path || '/' || n.name
        FROM nodes n
        JOIN tree t ON n.parent_id = t.id
    )
    SELECT path, file_id FROM tree WHERE type = 'file';
    """, (args.job_id,))

    files = cur.fetchall()

    client = MongoClient('mongodb://localhost:27017/')
    db = client.backups

    results = []
    for path, file_id in files:
        chunks = list(db.chunks.find({'file_id': file_id}).sort('chunk_index', 1))
        content = "".join([c['data'] for c in chunks])
        if not path.startswith('/'):
            path = '/' + path
        results.append({'path': path, 'content': content})

    results.sort(key=lambda x: x['path'])
    print(json.dumps(results))

if __name__ == '__main__':
    main()
EOF
    chmod +x /app/oracle_restore_tool

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app /data/db
