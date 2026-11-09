#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install dependencies for C++ and SQLite
    apt-get install -y sqlite3 libsqlite3-dev build-essential

    # Create user
    useradd -m -s /bin/bash user || true

    # Create the database and populate initial data
    mkdir -p /home/user
    sqlite3 /home/user/graph.db <<EOF
CREATE TABLE nodes(id INTEGER PRIMARY KEY, name TEXT);
CREATE TABLE edges(src INTEGER, dst INTEGER, weight REAL);
INSERT INTO nodes VALUES (10, 'A'), (100, 'B'), (200, 'C'), (300, 'D'), (400, 'E');
INSERT INTO edges VALUES (10, 200, 5.0);
INSERT INTO edges VALUES (10, 300, 10.0);
INSERT INTO edges VALUES (100, 400, 8.0);
INSERT INTO edges VALUES (300, 200, 2.0);
EOF

    # Set permissions
    chmod -R 777 /home/user
