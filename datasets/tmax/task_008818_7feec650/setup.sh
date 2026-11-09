#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create the database and populate it
    sqlite3 /home/user/routes.db <<EOF
CREATE TABLE edges (source TEXT, target TEXT, cost INTEGER);
INSERT INTO edges VALUES ('A', 'B', 10);
INSERT INTO edges VALUES ('A', 'C', 20);
INSERT INTO edges VALUES ('B', 'D', 15);
INSERT INTO edges VALUES ('C', 'D', 5);
INSERT INTO edges VALUES ('D', 'E', 30);
INSERT INTO edges VALUES ('E', 'F', 10);
EOF

    chmod -R 777 /home/user
