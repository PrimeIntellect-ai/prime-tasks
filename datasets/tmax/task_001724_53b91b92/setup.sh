#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang sqlite3 build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    mkdir -p /home/user/workspace
    mkdir -p /home/user/output

    # Create SQLite DB
    sqlite3 /home/user/data/researchers.db <<EOF
CREATE TABLE nodes (id INTEGER PRIMARY KEY, name TEXT);
INSERT INTO nodes (id, name) VALUES (1, 'Alice');
INSERT INTO nodes (id, name) VALUES (2, 'Bob');
INSERT INTO nodes (id, name) VALUES (3, 'Charlie');
INSERT INTO nodes (id, name) VALUES (4, 'Diana');
INSERT INTO nodes (id, name) VALUES (5, 'Eve');
EOF

    # Create CSV
    cat <<EOF > /home/user/data/edges.csv
source,target
1,2
2,3
3,5
1,4
4,5
EOF

    # Create JSON
    cat <<EOF > /home/user/data/topics.json
{
  "1": ["AI", "Graph"],
  "2": ["Biology"],
  "3": ["Chemistry"],
  "4": ["Data Science", "AI"],
  "5": ["Graph", "Bioinformatics"]
}
EOF

    chmod -R 777 /home/user
