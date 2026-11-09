#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 cargo rustc libsqlite3-dev pkg-config
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/etl
    sqlite3 /home/user/etl/supply_chain.db <<EOF
CREATE TABLE nodes (id INTEGER PRIMARY KEY, name TEXT, is_raw INTEGER);
CREATE TABLE edges (parent_id INTEGER, child_id INTEGER, lead_time_days INTEGER);

INSERT INTO nodes VALUES (1, 'Product_Omega', 0);
INSERT INTO nodes VALUES (2, 'Subassembly_A', 0);
INSERT INTO nodes VALUES (3, 'Subassembly_B', 0);
INSERT INTO nodes VALUES (4, 'Component_X', 0);
INSERT INTO nodes VALUES (5, 'Component_Y', 0);
INSERT INTO nodes VALUES (6, 'Raw_Iron', 1);
INSERT INTO nodes VALUES (7, 'Raw_Silicon', 1);

INSERT INTO edges VALUES (1, 2, 10);
INSERT INTO edges VALUES (1, 3, 5);
INSERT INTO edges VALUES (2, 4, 5);
INSERT INTO edges VALUES (3, 4, 15);
INSERT INTO edges VALUES (4, 6, 10);
INSERT INTO edges VALUES (3, 5, 2);
INSERT INTO edges VALUES (5, 7, 4);

CREATE INDEX idx_parent ON edges(parent_id);
CREATE INDEX idx_child ON edges(child_id);
EOF

    chmod -R 777 /home/user
