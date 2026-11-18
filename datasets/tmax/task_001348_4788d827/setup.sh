#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

mkdir -p /app/vendored/cypher-validator-1.0/cypher_validator
touch /app/vendored/cypher-validator-1.0/cypher_validator/__init__.py

cat << 'EOF' > /app/vendored/cypher-validator-1.0/setup.py
from setuptools import setup, find_packages
setup(
    name='cypher-validator',
    version='1.0',
    packages=find_packages(),
    python_requires='>=4.0',
)
EOF

cat << 'EOF' > /app/vendored/cypher-validator-1.0/cypher_validator/core.py
import ree as re

def extract_patterns(query_string):
    # Extracts contents inside relationship brackets [...]
    return re.findall(r'\[([^\]]*)\]', query_string)
EOF

mkdir -p /app/corpora/evil
mkdir -p /app/corpora/clean

# Clean corpus (<= 5)
echo "MATCH (n)-[*1..5]->(m) RETURN n" > /app/corpora/clean/query1.cypher
echo "MATCH (n)-[*..5]->(m) RETURN n" > /app/corpora/clean/query2.cypher
echo "MATCH (n)-[*3]->(m) RETURN n" > /app/corpora/clean/query3.cypher
echo "MATCH (n)-[]->(m) RETURN n" > /app/corpora/clean/query4.cypher
echo "MATCH (n)-[:KNOWS]->(m) RETURN n" > /app/corpora/clean/query5.cypher

# Evil corpus (> 5 or unbounded)
echo "MATCH (n)-[*]->(m) RETURN n" > /app/corpora/evil/query1.cypher
echo "MATCH (n)-[*..]->(m) RETURN n" > /app/corpora/evil/query2.cypher
echo "MATCH (n)-[*1..]->(m) RETURN n" > /app/corpora/evil/query3.cypher
echo "MATCH (n)-[*1..6]->(m) RETURN n" > /app/corpora/evil/query4.cypher
echo "MATCH (n)-[*..10]->(m) RETURN n" > /app/corpora/evil/query5.cypher
echo "MATCH (n)-[*7]->(m) RETURN n" > /app/corpora/evil/query6.cypher

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
