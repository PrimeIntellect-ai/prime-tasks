#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # Create authors.db
    sqlite3 authors.db "CREATE TABLE authors (id INTEGER PRIMARY KEY, name TEXT, institution_id INTEGER);"
    sqlite3 authors.db "INSERT INTO authors VALUES (1, 'Alice Adams', 1);"
    sqlite3 authors.db "INSERT INTO authors VALUES (2, 'Bob Brown', 2);"
    sqlite3 authors.db "INSERT INTO authors VALUES (3, 'Charlie Clark', 1);"
    sqlite3 authors.db "INSERT INTO authors VALUES (4, 'David Davis', 3);"
    sqlite3 authors.db "INSERT INTO authors VALUES (5, 'Eve Evans', 2);"
    sqlite3 authors.db "INSERT INTO authors VALUES (6, 'Frank Ford', 4);"

    # Create institutions.db
    sqlite3 institutions.db "CREATE TABLE institutions (id INTEGER PRIMARY KEY, name TEXT, country TEXT);"
    sqlite3 institutions.db "INSERT INTO institutions VALUES (1, 'MIT', 'USA');"
    sqlite3 institutions.db "INSERT INTO institutions VALUES (2, 'Oxford', 'UK');"
    sqlite3 institutions.db "INSERT INTO institutions VALUES (3, 'ETH', 'Switzerland');"
    sqlite3 institutions.db "INSERT INTO institutions VALUES (4, 'Stanford', 'USA');"

    # Create papers.jsonl
    cat << 'EOF' > papers.jsonl
{"paper_id": "P1", "title": "Deep Learning Trends", "author_ids": [1, 2, 3]}
{"paper_id": "P2", "title": "Quantum Computing", "author_ids": [2, 4, 5]}
{"paper_id": "P3", "title": "Graph Algorithms", "author_ids": [1, 4]}
{"paper_id": "P4", "title": "AI Ethics", "author_ids": [1, 2, 6]}
{"paper_id": "P5", "title": "Local Studies", "author_ids": [1, 3, 6]}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
