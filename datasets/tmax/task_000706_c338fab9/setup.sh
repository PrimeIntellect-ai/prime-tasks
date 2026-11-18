#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sqlite3
pip3 install pytest

useradd -m -s /bin/bash user || true
mkdir -p /home/user
cd /home/user

cat << 'EOF' > init.sql
CREATE TABLE entities (id INTEGER, type TEXT, name TEXT);
CREATE TABLE relations (source_id INTEGER, target_id INTEGER, rel_type TEXT);

-- Insert critical DB
INSERT INTO entities (id, type, name) VALUES (42, 'Database', 'DB-Core-Auth');

-- Insert other nodes
INSERT INTO entities (id, type, name) VALUES (101, 'Application', 'App-Frontend-Web');
INSERT INTO entities (id, type, name) VALUES (102, 'Application', 'App-Backend-API');
INSERT INTO entities (id, type, name) VALUES (103, 'Server', 'SRV-001');
INSERT INTO entities (id, type, name) VALUES (104, 'Application', 'App-Reporting');
INSERT INTO entities (id, type, name) VALUES (105, 'Database', 'DB-Logs');

-- Insert relations (edges)
INSERT INTO relations (source_id, target_id, rel_type) VALUES (42, 102, 'DEPENDS_ON');
INSERT INTO relations (source_id, target_id, rel_type) VALUES (102, 101, 'DEPENDS_ON');
INSERT INTO relations (source_id, target_id, rel_type) VALUES (102, 104, 'DEPENDS_ON');
INSERT INTO relations (source_id, target_id, rel_type) VALUES (105, 104, 'DEPENDS_ON');

-- Add some noise
WITH RECURSIVE cnt(x) AS (SELECT 1000 UNION ALL SELECT x+1 FROM cnt LIMIT 5000)
INSERT INTO entities (id, type, name) SELECT x, 'Unknown', 'Node-' || x FROM cnt;

WITH RECURSIVE cnt(x) AS (SELECT 1000 UNION ALL SELECT x+1 FROM cnt LIMIT 5000)
INSERT INTO relations (source_id, target_id, rel_type) SELECT x, x+1, 'LINKED' FROM cnt;
EOF

sqlite3 graph.db < init.sql
rm init.sql

cat << 'EOF' > query.sql
WITH RECURSIVE impact AS (
    SELECT target_id FROM relations WHERE source_id = 42
    UNION
    SELECT r.target_id FROM relations r
    INNER JOIN impact i ON r.source_id = i.target_id
)
SELECT e.name FROM entities e
JOIN impact i ON e.id = i.target_id
WHERE e.type = 'Application';
EOF

chown -R user:user /home/user
chmod -R 777 /home/user
