#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    sqlite3 /home/user/dataset.db <<EOF
CREATE TABLE concept_nodes (
    id INTEGER PRIMARY KEY,
    label TEXT
);

CREATE TABLE concept_edges (
    source_id INTEGER,
    target_id INTEGER,
    FOREIGN KEY(source_id) REFERENCES concept_nodes(id),
    FOREIGN KEY(target_id) REFERENCES concept_nodes(id)
);

INSERT INTO concept_nodes (id, label) VALUES 
(1, 'Graph Theory'),
(2, 'Centrality'),
(3, 'Data Modeling'),
(4, 'SQL'),
(5, 'NoSQL'),
(6, 'Mathematics'),
(7, 'Database Design'),
(8, 'Relational Algebra'),
(9, 'Document Stores'),
(10, 'Set Theory');

-- Node 2 will have the highest in-degree (4 incoming edges: 1->2, 3->2, 4->2, 5->2)
INSERT INTO concept_edges (source_id, target_id) VALUES 
(1, 2),
(3, 2),
(4, 2),
(5, 2);

-- Nodes with a path of length 2 to Node 2: 6->1, 7->3, 8->4, 9->5
INSERT INTO concept_edges (source_id, target_id) VALUES 
(6, 1),
(7, 3),
(8, 4),
(9, 5),
(10, 6); -- Path of length 3 to Node 2 (10->6->1->2)
EOF

    chmod -R 777 /home/user
