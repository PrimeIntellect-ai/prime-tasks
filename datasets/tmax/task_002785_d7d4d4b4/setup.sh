#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user

    # Create the setup script and run it
    cat << 'EOF' > /home/user/setup_db.sh
#!/bin/bash
sqlite3 /home/user/graph.db << 'SQL'
CREATE TABLE nodes (
    id TEXT PRIMARY KEY,
    label TEXT,
    properties_json TEXT
);

CREATE TABLE edges (
    source_id TEXT,
    target_id TEXT,
    rel_type TEXT
);

INSERT INTO nodes (id, label) VALUES 
('U1', 'User'), ('U2', 'User'), ('U3', 'User'), 
('U4', 'User'), ('U5', 'User'), ('U6', 'User'),
('U7', 'User');

-- U1 follows U2, U3, U4
INSERT INTO edges (source_id, target_id, rel_type) VALUES 
('U1', 'U2', 'FOLLOWS'),
('U1', 'U3', 'FOLLOWS'),
('U1', 'U4', 'FOLLOWS');

-- U5 follows U2, U3 (2 mutual with U1)
INSERT INTO edges (source_id, target_id, rel_type) VALUES 
('U5', 'U2', 'FOLLOWS'),
('U5', 'U3', 'FOLLOWS');

-- U6 follows U4 (1 mutual with U1)
INSERT INTO edges (source_id, target_id, rel_type) VALUES 
('U6', 'U4', 'FOLLOWS');

-- U7 follows U2, U3, U4 (3 mutual with U1)
INSERT INTO edges (source_id, target_id, rel_type) VALUES 
('U7', 'U2', 'FOLLOWS'),
('U7', 'U3', 'FOLLOWS'),
('U7', 'U4', 'FOLLOWS');

-- Random noise
INSERT INTO edges (source_id, target_id, rel_type) VALUES 
('U2', 'U5', 'FOLLOWS'),
('U1', 'M1', 'LIKES');
SQL
EOF
    chmod +x /home/user/setup_db.sh
    /home/user/setup_db.sh

    cat << 'EOF' > /home/user/find_mutual.sh
#!/bin/bash
# Bad implementation
echo "Not implemented correctly"
EOF
    chmod +x /home/user/find_mutual.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
