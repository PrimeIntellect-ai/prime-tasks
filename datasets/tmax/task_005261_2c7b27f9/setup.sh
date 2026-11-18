#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl libcurl4
    pip3 install pytest flask neo4j

    # Install Memgraph
    curl -L https://download.memgraph.com/memgraph/v2.15.0/ubuntu-22.04/memgraph_2.15.0-1_amd64.deb -o memgraph.deb
    dpkg -i memgraph.deb || apt-get install -f -y
    rm memgraph.deb

    mkdir -p /app /var/log/memgraph /var/lib/memgraph

    # Create Flask API
    cat << 'EOF' > /app/api.py
from flask import Flask, jsonify
import random

app = Flask(__name__)

# Pre-generate data to ensure fast response
random.seed(42)
DATA = [{"src": f"User{random.randint(1, 1000)}", "dst": f"User{random.randint(1, 1000)}", "action": "follows"} for _ in range(50000)]

@app.route('/stream')
def stream():
    return jsonify(DATA)

@app.route('/')
def index():
    return "OK"

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8080)
EOF

    # Create start_services.sh
    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
/usr/lib/memgraph/memgraph --telemetry-enabled=false --data-directory=/var/lib/memgraph > /var/log/memgraph.log 2>&1 &
python3 /app/api.py > /var/log/api.log 2>&1 &
sleep 5
EOF
    chmod +x /app/start_services.sh

    useradd -m -s /bin/bash user || true

    # Create badly written ETL script
    cat << 'EOF' > /home/user/etl_pipeline.py
import urllib.request
import json
from neo4j import GraphDatabase

def run():
    req = urllib.request.urlopen("http://127.0.0.1:8080/stream")
    data = json.loads(req.read())

    driver = GraphDatabase.driver("bolt://127.0.0.1:7687")
    with driver.session() as session:
        for record in data:
            session.run("MERGE (s:User {id: $src}) MERGE (d:User {id: $dst}) MERGE (s)-[:FOLLOWS]->(d)", src=record["src"], dst=record["dst"])

if __name__ == "__main__":
    run()
EOF

    chmod -R 777 /home/user /app /var/lib/memgraph /var/log/memgraph
