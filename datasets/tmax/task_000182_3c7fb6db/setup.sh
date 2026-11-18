#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl wget sudo postgresql postgresql-contrib
    pip3 install pytest psycopg2-binary neo4j

    # Install Memgraph
    wget https://download.memgraph.com/memgraph/v2.12.0/ubuntu-22.04/memgraph_2.12.0-1_amd64.deb
    dpkg -i memgraph_2.12.0-1_amd64.deb || apt-get install -f -y
    rm memgraph_2.12.0-1_amd64.deb

    mkdir -p /app

    # Create start_services.sh
    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
service postgresql start
sudo -u postgres psql -c "ALTER USER postgres WITH PASSWORD 'postgres';"
sudo -u postgres psql -c "CREATE DATABASE analytics;" || true

# Start memgraph
/usr/lib/memgraph/memgraph --log-level=WARNING &

sleep 5

cat << 'SQL' > /tmp/init.sql
CREATE TABLE IF NOT EXISTS raw_events (
    event_id SERIAL PRIMARY KEY,
    user_id INTEGER,
    event_timestamp TIMESTAMP,
    event_type VARCHAR
);
TRUNCATE raw_events;
INSERT INTO raw_events (user_id, event_timestamp, event_type)
SELECT 
    (random() * 1000)::int,
    timestamp '2023-01-01 00:00:00' + random() * (timestamp '2023-01-31 23:59:59' - timestamp '2023-01-01 00:00:00'),
    (ARRAY['home', 'search', 'view_item', 'checkout', 'login', 'logout'])[floor(random() * 6 + 1)]
FROM generate_series(1, 50000);
SQL
PGPASSWORD=postgres psql -U postgres -d analytics -h localhost -f /tmp/init.sql
EOF
    chmod +x /app/start_services.sh

    # Create verify_performance.py
    cat << 'EOF' > /app/verify_performance.py
import time
from neo4j import GraphDatabase

def main():
    driver = GraphDatabase.driver("bolt://localhost:7687")
    with open("/home/user/target_query.cypher") as f:
        query = f.read()

    with driver.session() as session:
        session.run(query)

    start = time.time()
    for _ in range(50):
        with driver.session() as session:
            result = session.run(query)
            record = result.single()
    duration = (time.time() - start) / 50.0

    assert duration < 0.015, f"Query too slow: {duration}s"
    print("Performance test passed.")

if __name__ == "__main__":
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
