#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip postgresql redis-server sudo
    pip3 install pytest psycopg2-binary flask

    mkdir -p /app/corpus/clean /app/corpus/evil

    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
PG_VERSION=$(ls /etc/postgresql/ | head -n 1)
sed -i 's/peer/trust/g' /etc/postgresql/$PG_VERSION/main/pg_hba.conf
sed -i 's/scram-sha-256/trust/g' /etc/postgresql/$PG_VERSION/main/pg_hba.conf
sed -i 's/md5/trust/g' /etc/postgresql/$PG_VERSION/main/pg_hba.conf

service redis-server start
service postgresql start

su - postgres -c "psql -c \"CREATE USER researcher WITH PASSWORD 'password';\""
su - postgres -c "psql -c \"CREATE DATABASE research_db OWNER researcher;\""

su - postgres -c "psql -d research_db -c \"CREATE TABLE papers (id SERIAL PRIMARY KEY, title TEXT, published_year INT, domain_id INT, citation_count INT);\""
su - postgres -c "psql -d research_db -c \"CREATE TABLE citations (paper_id INT, cited_paper_id INT);\""

su - postgres -c "psql -d research_db -c \"INSERT INTO papers (title, published_year, domain_id, citation_count) SELECT 'Paper ' || i, 2000 + (i % 20), i % 10, i % 100 FROM generate_series(1, 100000) as i;\""
su - postgres -c "psql -d research_db -c \"INSERT INTO citations (paper_id, cited_paper_id) SELECT (random() * 99999 + 1)::int, (random() * 99999 + 1)::int FROM generate_series(1, 500000);\""

cat << 'PYEOF' > /app/flask_api.py
from flask import Flask
app = Flask(__name__)
@app.route('/')
def hello(): return 'Hello'
if __name__ == '__main__': app.run(port=5000)
PYEOF

nohup python3 /app/flask_api.py > /dev/null 2>&1 &
EOF
    chmod +x /app/start_services.sh

    cat << 'EOF' > /app/corpus/clean/query1.sql
WITH RECURSIVE cite_tree AS (
    SELECT cited_paper_id FROM citations WHERE paper_id = 100
    UNION
    SELECT c.cited_paper_id FROM citations c INNER JOIN cite_tree ct ON c.paper_id = ct.cited_paper_id
) SELECT * FROM cite_tree;
EOF

    cat << 'EOF' > /app/corpus/clean/query2.sql
SELECT id, title, rank() OVER (PARTITION BY domain_id ORDER BY published_year DESC) FROM papers WHERE domain_id = 5;
EOF

    cat << 'EOF' > /app/corpus/evil/query1.sql
SELECT * FROM papers WHERE title LIKE '%deep learning%';
EOF

    cat << 'EOF' > /app/corpus/evil/query2.sql
SELECT p1.id, p2.id FROM papers p1, papers p2 WHERE p1.citation_count + p2.citation_count > 10000;
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
