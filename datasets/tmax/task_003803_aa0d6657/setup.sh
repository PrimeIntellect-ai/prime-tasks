#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 golang
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > /home/user/setup.sql
CREATE TABLE nodes (
    id TEXT PRIMARY KEY,
    department TEXT
);

CREATE TABLE edges (
    src TEXT,
    dst TEXT,
    timestamp INTEGER
);

INSERT INTO nodes (id, department) VALUES 
('N01', 'Engineering'), ('N02', 'Engineering'), ('N03', 'Engineering'), ('N04', 'Engineering'), ('N05', 'Engineering'),
('N06', 'Sales'), ('N07', 'Sales'), ('N08', 'Sales'), ('N09', 'Sales'),
('N10', 'Marketing'), ('N11', 'Marketing'), ('N12', 'Marketing');

INSERT INTO edges (src, dst, timestamp) VALUES
('N01', 'N02', 100), ('N01', 'N02', 200),
('N02', 'N03', 150),
('N03', 'N01', 300), ('N03', 'N01', 50),
('N01', 'N04', 100),
('N04', 'N05', 100),
('N05', 'N01', 100),
('N06', 'N07', 100), ('N06', 'N07', 110),
('N07', 'N08', 100),
('N08', 'N09', 100),
('N09', 'N06', 100),
('N06', 'N08', 100),
('N10', 'N11', 100),
('N11', 'N12', 100),
('N12', 'N10', 100),
('N01', 'N06', 100),
('N06', 'N10', 100);
EOF

    sqlite3 /home/user/network.db < /home/user/setup.sql
    rm /home/user/setup.sql

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
