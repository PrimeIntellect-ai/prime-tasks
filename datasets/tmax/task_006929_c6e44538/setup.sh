#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/knowledge_graph.db <<EOF
CREATE TABLE entities (
    id VARCHAR(50) PRIMARY KEY,
    attributes TEXT
);

CREATE TABLE relations (
    from_id VARCHAR(50),
    to_id VARCHAR(50),
    relation_type VARCHAR(50)
);

INSERT INTO entities (id, attributes) VALUES 
('e1', '{"name": "Zoe Davis", "type": "Employee", "title": "CEO"}'),
('e2', '{"name": "Bob Johnson", "type": "Employee", "title": "VP"}'),
('e3', '{"name": "Charlie Brown", "type": "Employee", "title": "Director"}'),
('e4', '{"name": "Diana Prince", "type": "Employee", "title": "Manager"}'),
('e5', '{"name": "Alice Smith", "type": "Employee", "title": "Engineer"}'),
('e6', '{"name": "Main Office", "type": "Building"}');

INSERT INTO relations (from_id, to_id, relation_type) VALUES 
('e5', 'e4', 'REPORTS_TO'),
('e4', 'e3', 'REPORTS_TO'),
('e3', 'e2', 'REPORTS_TO'),
('e2', 'e1', 'REPORTS_TO'),
('e5', 'e6', 'WORKS_IN');
EOF

    chmod -R 777 /home/user
