#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang sqlite3
pip3 install pytest

mkdir -p /home/user
cd /home/user

cat << 'EOF' > setup_db.sql
CREATE TABLE nodes (id TEXT PRIMARY KEY, type TEXT);
CREATE TABLE edges (source TEXT, target TEXT, relation TEXT);
CREATE TABLE metrics (node_id TEXT, score REAL, recorded_at DATETIME);

INSERT INTO nodes (id, type) VALUES ('ROOT', 'core'), ('A', 'concept'), ('B', 'concept'), ('C', 'concept');
INSERT INTO edges (source, target, relation) VALUES 
('ROOT', 'A', 'depends_on'),
('ROOT', 'B', 'depends_on'),
('ROOT', 'C', 'relates_to');

INSERT INTO metrics (node_id, score, recorded_at) VALUES 
('A', 5.0, '2023-01-01'),
('A', 3.0, '2023-01-02'),
('A', -1.0, '2023-01-03'),
('B', -2.0, '2023-01-01'),
('B', 10.0, '2023-01-02'),
('C', 100.0, '2023-01-01');

CREATE INDEX idx_metrics_node ON metrics(node_id);
EOF

sqlite3 research.db < setup_db.sql
rm setup_db.sql

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
