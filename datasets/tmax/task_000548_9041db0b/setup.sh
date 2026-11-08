#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        postgresql \
        redis-server \
        sudo

    pip3 install pytest python-dotenv psycopg2-binary redis pyinstaller

    mkdir -p /app
    mkdir -p /home/user

    # Create schema.sql
    cat << 'EOF' > /app/schema.sql
CREATE DATABASE research_db;
CREATE USER researcher WITH PASSWORD 'password123';
GRANT ALL PRIVILEGES ON DATABASE research_db TO researcher;

\c research_db;

CREATE TABLE datasets (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255),
    is_active BOOLEAN
);

CREATE TABLE dataset_dependencies (
    source_id INTEGER REFERENCES datasets(id),
    target_id INTEGER REFERENCES datasets(id),
    PRIMARY KEY (source_id, target_id)
);

GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO researcher;

INSERT INTO datasets (id, name, is_active)
SELECT i, 'Dataset ' || i, (i % 5 != 0)
FROM generate_series(1, 100) AS i;

INSERT INTO dataset_dependencies (source_id, target_id)
SELECT 
    (random() * 99 + 1)::int,
    (random() * 99 + 1)::int
FROM generate_series(1, 150)
ON CONFLICT DO NOTHING;
EOF

    # Create start_services.sh
    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
service postgresql start
service redis-server start

# Wait for postgres to be ready
until sudo -u postgres psql -c '\q' 2>/dev/null; do
    sleep 1
done

# Initialize schema if db doesn't exist
if ! sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw research_db; then
    sudo -u postgres psql -f /app/schema.sql
fi
EOF
    chmod +x /app/start_services.sh

    # Create oracle python script
    cat << 'EOF' > /app/oracle_source.py
import os
import argparse
import psycopg2
import json

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--dataset-id', type=int, required=True)
    parser.add_argument('--max-depth', type=int, required=True)
    parser.add_argument('--limit', type=int, required=True)
    parser.add_argument('--offset', type=int, required=True)
    args = parser.parse_args()

    conn = psycopg2.connect(
        host='127.0.0.1',
        port=5432,
        dbname='research_db',
        user='researcher',
        password='password123'
    )
    cursor = conn.cursor()

    query = """
    WITH RECURSIVE traverse AS (
        SELECT id, 0 AS depth
        FROM datasets
        WHERE id = %s

        UNION

        SELECT dep.target_id, t.depth + 1
        FROM traverse t
        JOIN dataset_dependencies dep ON t.id = dep.source_id
        WHERE t.depth < %s
    )
    SELECT DISTINCT t.id
    FROM traverse t
    JOIN datasets d ON t.id = d.id
    WHERE d.is_active = true
    ORDER BY t.id
    LIMIT %s OFFSET %s;
    """
    cursor.execute(query, (args.dataset_id, args.max_depth, args.limit, args.offset))
    results = cursor.fetchall()

    ids = [r[0] for r in results]
    print(json.dumps(ids))

if __name__ == '__main__':
    main()
EOF

    # Compile oracle
    cd /app
    pyinstaller --onefile oracle_source.py
    mv dist/oracle_source /app/oracle_query
    chmod +x /app/oracle_query
    rm -rf build dist oracle_source.py oracle_source.spec

    # Create config.env
    cat << 'EOF' > /home/user/config.env
DB_HOST=localhost
DB_PORT=5432
DB_NAME=wrong_db
DB_USER=wrong_user
DB_PASS=wrong_pass
REDIS_HOST=localhost
REDIS_PORT=6379
EOF

    # Create dataset_query.py
    cat << 'EOF' > /home/user/dataset_query.py
import os
import argparse
import psycopg2
import redis
import json
from dotenv import load_dotenv

load_dotenv('/home/user/config.env')

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--dataset-id', type=int, required=True)
    parser.add_argument('--max-depth', type=int, required=True)
    parser.add_argument('--limit', type=int, required=True)
    parser.add_argument('--offset', type=int, required=True)
    args = parser.parse_args()

    conn = psycopg2.connect(
        host=os.environ.get('DB_HOST'),
        port=os.environ.get('DB_PORT'),
        dbname=os.environ.get('DB_NAME'),
        user=os.environ.get('DB_USER'),
        password=os.environ.get('DB_PASS')
    )
    cursor = conn.cursor()

    # Broken query with cross join
    query = """
    SELECT d2.id 
    FROM datasets d1, datasets d2, dataset_dependencies dep 
    WHERE d1.id = %s
    """
    cursor.execute(query, (args.dataset_id,))
    results = cursor.fetchall()

    ids = list(set([r[0] for r in results]))
    print(json.dumps(ids))

if __name__ == '__main__':
    main()
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
