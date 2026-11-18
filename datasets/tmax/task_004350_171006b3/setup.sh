#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 python3-pip \
        redis-server \
        wget \
        curl \
        default-jre \
        jq

    pip3 install pytest flask neo4j redis

    # Install Neo4j
    mkdir -p /app
    cd /app
    wget -q https://neo4j.com/artifact.php?name=neo4j-community-4.4.20-unix.tar.gz -O neo4j.tar.gz
    tar -xzf neo4j.tar.gz
    mv neo4j-community-4.4.20 neo4j
    rm neo4j.tar.gz

    # Configure Neo4j to not require password change on first login and set initial password
    bin/neo4j-admin set-initial-password password || true

    # Create user
    useradd -m -s /bin/bash user || true

    # Create corpora
    mkdir -p /home/user/corpora
    echo -e "Acme Corp\nGlobalTech\nSmith & Sons\nRetailHQ\nTech_Data-2023" > /home/user/corpora/clean.csv
    echo -e "Acme' OR 1=1 //\n'); MATCH (n) DETACH DELETE n;\nGlobalTech' RETURN 1 UNION MATCH (n) RETURN n.password //\nCALL db.labels() YIELD label\n' SET n.admin = true //" > /home/user/corpora/evil.csv

    # Create config.json
    cat << 'EOF' > /home/user/config.json
{
    "neo4j_uri": "",
    "neo4j_user": "",
    "neo4j_password": "",
    "redis_uri": ""
}
EOF

    # Create app.py
    cat << 'EOF' > /home/user/app.py
from flask import Flask, jsonify
import json
import redis
from neo4j import GraphDatabase

app = Flask(__name__)

@app.route('/health')
def health():
    try:
        with open('/home/user/config.json', 'r') as f:
            config = json.load(f)

        # Check Redis
        r = redis.Redis.from_url(config.get('redis_uri', ''))
        r.ping()

        # Check Neo4j
        driver = GraphDatabase.driver(
            config.get('neo4j_uri', ''),
            auth=(config.get('neo4j_user', ''), config.get('neo4j_password', ''))
        )
        driver.verify_connectivity()
        driver.close()

        return jsonify({"status": "ok"})
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

    # Create start_services.sh
    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
service redis-server start
/app/neo4j/bin/neo4j start
sleep 10
python3 /home/user/app.py &
EOF
    chmod +x /app/start_services.sh

    chmod -R 777 /home/user
