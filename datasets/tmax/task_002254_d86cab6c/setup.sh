#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget curl openjdk-11-jre-headless jq netcat
    pip3 install --default-timeout=100 pytest pymongo neo4j

    # Install MongoDB
    cd /tmp
    wget -qO- https://fastdl.mongodb.org/linux/mongodb-linux-x86_64-ubuntu2204-6.0.8.tgz | tar xz
    mv mongodb-linux-*/bin/* /usr/local/bin/
    mkdir -p /data/db

    # Install Neo4j
    wget -qO- "https://neo4j.com/artifact.php?name=neo4j-community-4.4.23-unix.tar.gz" | tar xz
    mv neo4j-community-* /opt/neo4j
    sed -i 's/#dbms.security.auth_enabled=false/dbms.security.auth_enabled=false/' /opt/neo4j/conf/neo4j.conf

    # Create directories
    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    # Write start_services.sh
    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
mongod --fork --logpath /var/log/mongod.log
/opt/neo4j/bin/neo4j start

# Wait for MongoDB
until nc -z localhost 27017; do sleep 1; done
# Wait for Neo4j
until nc -z localhost 7687; do sleep 1; done

# Seed MongoDB
python3 -c "
from pymongo import MongoClient
client = MongoClient('mongodb://localhost:27017/')
db = client.biomed
db.authors.insert_many([
    {'author_id': 'alice', 'trust_score': 0.9},
    {'author_id': 'bob', 'trust_score': 0.2}
])
"

# Seed Neo4j
python3 -c "
from neo4j import GraphDatabase
driver = GraphDatabase.driver('bolt://localhost:7687', auth=None)
with driver.session() as session:
    session.run(\"CREATE (p1:Paper {paper_id: 'P001'}), (p2:Paper {paper_id: 'P002'}), (p3:Paper {paper_id: 'EVIL_TARGET'}), (p2)-[:CITES]->(p3)\")
"
EOF
    chmod +x /app/start_services.sh

    # Generate test corpus
    cat << 'EOF' > /app/corpora/clean/clean1.json
{"paper_id": "C001", "author_id": "alice", "cites": ["P001"]}
EOF
    cat << 'EOF' > /app/corpora/evil/evil1.json
{"paper_id": "E001", "author_id": {"$ne": null}, "cites": ["P001"]}
EOF
    cat << 'EOF' > /app/corpora/evil/evil2.json
{"paper_id": "E002", "author_id": "bob", "cites": ["P001"]}
EOF
    cat << 'EOF' > /app/corpora/evil/evil3.json
{"paper_id": "E003", "author_id": "alice", "cites": ["NONEXISTENT"]}
EOF
    cat << 'EOF' > /app/corpora/evil/evil4.json
{"paper_id": "EVIL_TARGET", "author_id": "alice", "cites": ["P002"]}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
