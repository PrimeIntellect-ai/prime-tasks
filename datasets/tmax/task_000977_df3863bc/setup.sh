#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sqlite3
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user
cd /home/user

sqlite3 citation_network.db << 'EOF'
CREATE TABLE papers (id INTEGER PRIMARY KEY, title TEXT, year INTEGER);
CREATE TABLE citations (source_id INTEGER, target_id INTEGER);

-- Insert dummy data
INSERT INTO papers (id, title, year) VALUES 
(1, 'Graph Theory Basics', 2010),
(2, 'Advanced Graph Analytics', 2015),
(3, 'Modern AI', 2019),
(4, 'Deep Learning Innovations', 2020),
(5, 'Future of Tech', 2021),
(6, 'Old Paper', 1999),
(7, 'Another Old Paper', 2005);

-- Insert citations
INSERT INTO citations (source_id, target_id) VALUES 
(2, 1),
(3, 1),
(4, 1),
(5, 1),
(6, 1),
(3, 2),
(4, 2),
(5, 2),
(4, 3),
(5, 3),
(5, 4);

CREATE INDEX idx_citations_target ON citations(target_id);
EOF

chown -R user:user /home/user
chmod -R 777 /home/user
