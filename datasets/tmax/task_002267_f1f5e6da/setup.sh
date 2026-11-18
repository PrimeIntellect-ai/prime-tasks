#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/setup_db.sql
CREATE TABLE nodes (id INTEGER PRIMARY KEY, name TEXT, category TEXT);
CREATE TABLE edges (source_id INTEGER, target_id INTEGER);

INSERT INTO nodes (id, name, category) VALUES 
(1, 'Dataset_A', 'Genomics'),
(2, 'Dataset_B', 'Genomics'),
(3, 'Dataset_C', 'Proteomics'),
(4, 'Dataset_D', 'Transcriptomics'),
(5, 'Dataset_E', 'Genomics'),
(6, 'Dataset_F', 'Proteomics'),
(7, 'Dataset_G', 'Transcriptomics');

INSERT INTO edges (source_id, target_id) VALUES 
(1, 2),
(2, 3),
(4, 3),
(5, 1),
(6, 2),
(7, 6);
EOF

    sqlite3 /home/user/research_data.db < /home/user/setup_db.sql
    rm /home/user/setup_db.sql

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
