#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip postgresql redis-server sudo
    pip3 install pytest psycopg2-binary redis

    mkdir -p /app
    mkdir -p /var/lib/postgresql/data
    chown -R postgres:postgres /var/lib/postgresql

    cat << 'EOF' > /app/generate_data.py
import psycopg2
from datetime import datetime, timedelta
import random

conn = psycopg2.connect(dbname="backups", user="postgres", host="localhost")
cur = conn.cursor()

jobs = []
for i in range(1, 20001):
    job_name = f"job_{i % 1000}"
    created_at = datetime.now() - timedelta(days=random.randint(0, 100))
    jobs.append((i, job_name, 'SUCCESS', created_at))

cur.executemany("INSERT INTO backup_jobs (id, job_name, status, created_at) VALUES (%s, %s, %s, %s)", jobs)

deps = []
for i in range(1, 19999):
    deps.append((i, i+1))
    if i % 10 == 0:
        deps.append((i, i+2))

cur.executemany("INSERT INTO job_dependencies (parent_job_id, child_job_id) VALUES (%s, %s)", deps)

conn.commit()
EOF

    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
chown -R postgres:postgres /var/lib/postgresql
su - postgres -c "/usr/lib/postgresql/14/bin/initdb -D /var/lib/postgresql/data"
su - postgres -c "/usr/lib/postgresql/14/bin/pg_ctl -D /var/lib/postgresql/data start"
redis-server --daemonize yes
sleep 3
su - postgres -c "psql -c 'CREATE DATABASE backups;'"
su - postgres -c "psql -d backups -c 'CREATE TABLE backup_jobs (id INT PRIMARY KEY, job_name VARCHAR, status VARCHAR, created_at TIMESTAMP); CREATE TABLE job_dependencies (parent_job_id INT, child_job_id INT); CREATE INDEX idx_parent ON job_dependencies(parent_job_id);'"
python3 /app/generate_data.py
EOF
    chmod +x /app/start_services.sh

    cat << 'EOF' > /app/backup_extractor.py
import sys
import psycopg2
import redis
import json

def get_downstream(job_id, conn):
    cur = conn.cursor()
    cur.execute("SELECT child_job_id FROM job_dependencies WHERE parent_job_id = %s", (job_id,))
    children = [row[0] for row in cur.fetchall()]
    all_deps = list(children)
    for child in children:
        all_deps.extend(get_downstream(child, conn))
    return all_deps

def main():
    if len(sys.argv) < 2:
        sys.exit(1)
    start_id = int(sys.argv[1])
    conn = psycopg2.connect(dbname="backups", user="postgres", host="localhost")
    deps = get_downstream(start_id, conn)

    jobs = []
    cur = conn.cursor()
    for d in set(deps):
        cur.execute("SELECT id, job_name, created_at FROM backup_jobs WHERE id = %s", (d,))
        jobs.append(cur.fetchone())

    filtered = {}
    for j in jobs:
        name = j[1]
        if name not in filtered or j[2] > filtered[name][2]:
            filtered[name] = j

    final_ids = [j[0] for j in sorted(filtered.values(), key=lambda x: x[2])]

    r = redis.Redis(host='localhost', port=6379, db=0)
    r.set(f"restore_chain:{start_id}", json.dumps(final_ids))

if __name__ == "__main__":
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
