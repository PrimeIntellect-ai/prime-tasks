#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        imagemagick \
        sqlite3

    pip3 install pytest

    # Create directories
    mkdir -p /app/corpora/evil
    mkdir -p /app/corpora/clean
    mkdir -p /home/user

    # Create user
    useradd -m -s /bin/bash user || true

    # Generate schema clue image
    convert -size 600x100 xc:white -pointsize 24 -fill black -draw "text 10,50 'ROOT_NODE: 1042, EDGE_TYPE: \'FIBER\''" /app/schema_clue.png

    # Create SQLite database
    cat << 'EOF' > /tmp/setup.sql
CREATE TABLE nodes (id INTEGER PRIMARY KEY, hostname TEXT);
CREATE TABLE edges (source INTEGER, target INTEGER, cost INTEGER, edge_type TEXT);
CREATE INDEX idx_edges_corrupt ON edges(source, target);

INSERT INTO nodes (id, hostname) VALUES (1042, 'root'), (305, 'nodeA'), (992, 'nodeB'), (2000, 'nodeC');
INSERT INTO edges (source, target, cost, edge_type) VALUES (1042, 305, 10, 'FIBER'), (305, 992, 5, 'FIBER'), (992, 2000, 15, 'FIBER'), (1042, 992, 20, 'FIBER');
EOF
    sqlite3 /home/user/network_topology.db < /tmp/setup.sql
    rm /tmp/setup.sql

    # Populate corpora
    echo "SELECT * FROM nodes; DROP TABLE edges;" > /app/corpora/evil/evil1.sql
    echo "SELECT * FROM nodes WHERE id = 1 -- comment" > /app/corpora/evil/evil2.sql
    echo "UPDATE nodes SET hostname='pwned';" > /app/corpora/evil/evil3.sql

    echo "SELECT * FROM nodes;" > /app/corpora/clean/clean1.sql
    echo "WITH RECURSIVE cte AS (SELECT 1) SELECT * FROM cte;" > /app/corpora/clean/clean2.sql

    # Set permissions
    chmod -R 777 /home/user
    chmod -R 777 /app
