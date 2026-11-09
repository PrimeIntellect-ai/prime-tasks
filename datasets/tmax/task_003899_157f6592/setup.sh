#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak gcc
    pip3 install pytest

    mkdir -p /app/verifier/corpus

    # Generate the audio file
    espeak -w /app/backup_memo.wav "The attacker is exploiting the backup pipeline by injecting Cypher MATCH clauses combined with SQL window functions. Specifically, any query that contains the string 'MATCH (n) DETACH DELETE n' or 'OVER (PARTITION BY 1=1)' is malicious and must be blocked. All other standard SPARQL SELECTs, Cypher MATCHes with pagination, and standard SQL window functions like 'OVER (PARTITION BY user_id)' are safe."

    # Create evil corpus
    cat << 'EOF' > /app/verifier/corpus/evil.txt
MATCH (n) DETACH DELETE n;
SELECT *, ROW_NUMBER() OVER (PARTITION BY 1=1) FROM users;
EOF

    # Create clean corpus
    cat << 'EOF' > /app/verifier/corpus/clean.txt
MATCH (n:Backup) RETURN n ORDER BY n.date DESC SKIP 10 LIMIT 50;
SELECT name, MAX(salary) OVER (PARTITION BY department_id) FROM employees;
PREFIX foaf: <http://xmlns.com/foaf/0.1/> SELECT ?name WHERE { ?x foaf:name ?name }
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
