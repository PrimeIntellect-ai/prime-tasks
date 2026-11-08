#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/network.db <<EOF
CREATE TABLE vertices (
    v_id INTEGER PRIMARY KEY,
    v_name TEXT UNIQUE NOT NULL
);

CREATE TABLE edges (
    source_id INTEGER,
    target_id INTEGER,
    weight REAL,
    FOREIGN KEY(source_id) REFERENCES vertices(v_id),
    FOREIGN KEY(target_id) REFERENCES vertices(v_id)
);

INSERT INTO vertices (v_id, v_name) VALUES
(1, 'Protein_A'),
(2, 'Gene_B'),
(3, 'Chemical_C'),
(4, 'Protein_D'),
(5, 'Disease_Z'),
(6, 'Decoy_E');

-- Path 1: A -> B -> Z (Weight: 10 + 20 = 30) (2 hops)
INSERT INTO edges (source_id, target_id, weight) VALUES (1, 2, 10.0);
INSERT INTO edges (source_id, target_id, weight) VALUES (2, 5, 20.0);

-- Path 2: A -> C -> D -> Z (Weight: 5 + 5 + 8 = 18) (3 hops)
INSERT INTO edges (source_id, target_id, weight) VALUES (1, 3, 5.0);
INSERT INTO edges (source_id, target_id, weight) VALUES (3, 4, 5.0);
INSERT INTO edges (source_id, target_id, weight) VALUES (4, 5, 8.0);

-- Path 3: A -> E -> Z (Weight: 2 + 50 = 52) (2 hops)
INSERT INTO edges (source_id, target_id, weight) VALUES (1, 6, 2.0);
INSERT INTO edges (source_id, target_id, weight) VALUES (6, 5, 50.0);
EOF

    chmod -R 777 /home/user
