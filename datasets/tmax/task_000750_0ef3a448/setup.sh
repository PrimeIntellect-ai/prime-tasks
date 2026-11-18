#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sqlite3
pip3 install pytest networkx

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/setup_db.sql
CREATE TABLE nodes (node_id INTEGER PRIMARY KEY, node_name TEXT);
CREATE TABLE edges (source INTEGER, target INTEGER, weight REAL);

INSERT INTO nodes (node_id, node_name) VALUES 
(1, 'Alpha'), (2, 'Bravo'), (3, 'Charlie'), (4, 'Delta'), (5, 'Echo Hub');

-- Make Echo Hub (5) the clear most central node, followed by Alpha (1)
INSERT INTO edges (source, target, weight) VALUES
(1, 5, 1.0),
(2, 5, 2.0),
(3, 5, 1.5),
(4, 5, 0.5),
(5, 1, 1.0),
(2, 1, 1.0),
(3, 1, 0.5);
EOF
sqlite3 /home/user/network.db < /tmp/setup_db.sql
rm /tmp/setup_db.sql

cat << 'EOF' > /home/user/slow_query.sql
SELECT e1.source, e2.target, SUM(e1.weight * e2.weight) as two_hop_weight
FROM edges e1
JOIN edges e2 ON e1.target = e2.source
GROUP BY e1.source, e2.target;
EOF

chmod -R 777 /home/user
