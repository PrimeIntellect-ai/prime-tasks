#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sqlite3 espeak
pip3 install pytest

mkdir -p /app
# Generate audio fixture using espeak directly to avoid pyttsx3 headless issues
espeak -w /app/compliance_alert.wav "The audit target is BlackOasis. The traversal depth is two."

mkdir -p /home/user
# Create the SQLite graph database
sqlite3 /home/user/audit_records.db <<'EOF'
CREATE TABLE nodes (
    node_id INTEGER PRIMARY KEY,
    entity_name TEXT UNIQUE NOT NULL
);

CREATE TABLE edges (
    source_id INTEGER,
    target_id INTEGER,
    transaction_type TEXT,
    FOREIGN KEY(source_id) REFERENCES nodes(node_id),
    FOREIGN KEY(target_id) REFERENCES nodes(node_id)
);

INSERT INTO nodes (node_id, entity_name) VALUES
(1, 'BlackOasis'),
(2, 'Shadow_Trust'),
(3, 'Global_Holdings'),
(4, 'Crimson_Shell'),
(5, 'Frontier_Corp'),
(6, 'Innocent_LLC');

-- Edges: Undirected conceptual graph, but stored as directed. Agent must handle standard traversal.
-- Depth 1 from BlackOasis: Shadow_Trust, Global_Holdings
INSERT INTO edges (source_id, target_id, transaction_type) VALUES (1, 2, 'transfer');
INSERT INTO edges (source_id, target_id, transaction_type) VALUES (1, 3, 'ownership');

-- Depth 2 from BlackOasis: Crimson_Shell (via 2), Frontier_Corp (via 3)
INSERT INTO edges (source_id, target_id, transaction_type) VALUES (2, 4, 'loan');
INSERT INTO edges (source_id, target_id, transaction_type) VALUES (3, 5, 'transfer');

-- Depth 3 from BlackOasis: Innocent_LLC (via 5) -> Should NOT be included if depth is 2
INSERT INTO edges (source_id, target_id, transaction_type) VALUES (5, 6, 'payment');

-- Reverse edges to ensure agent handles bidirectional or at least the graph as inserted
INSERT INTO edges (source_id, target_id, transaction_type) VALUES (4, 2, 'repayment');

CREATE INDEX idx_edges_source ON edges(source_id);
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
