#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 espeak
    pip3 install pytest

    mkdir -p /app
    espeak -w /app/incident_report.wav "We had a severe incident where backup dependency queries caused an implicit cross join, bringing down the DB. In Cypher, this happens when a MATCH clause has a comma separating node patterns without any relationships, causing a Cartesian product. For your filter, any Cypher query containing a MATCH clause with a comma between two node definitions, like MATCH parenthesis a parenthesis comma parenthesis b parenthesis, is considered evil. Clean queries either use multiple MATCH clauses or explicitly link nodes with relationships using dashes and brackets. Your script should return exit code 1 for these evil implicit cross join queries, and 0 for clean ones."

    sqlite3 /app/backup_graph.db "CREATE TABLE nodes (job_id TEXT PRIMARY KEY);"
    sqlite3 /app/backup_graph.db "CREATE TABLE edges (source_job TEXT, target_job TEXT);"
    sqlite3 /app/backup_graph.db "INSERT INTO nodes VALUES ('jobA'), ('jobB'), ('jobC'), ('jobD');"
    sqlite3 /app/backup_graph.db "INSERT INTO edges VALUES ('jobA', 'jobB'), ('jobA', 'jobC'), ('jobC', 'jobD');"

    mkdir -p /verify/corpus/evil /verify/corpus/clean
    cat << 'EOF' > /verify/corpus/evil/evil1.cypher
MATCH (a), (b)
RETURN a, b
EOF
    cat << 'EOF' > /verify/corpus/evil/evil2.cypher
MATCH (n:Person) , (m:Movie)
RETURN n, m
EOF
    cat << 'EOF' > /verify/corpus/clean/clean1.cypher
MATCH (a)-[:KNOWS]->(b)
RETURN a, b
EOF
    cat << 'EOF' > /verify/corpus/clean/clean2.cypher
MATCH (a)
MATCH (b)
RETURN a, b
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app /verify
