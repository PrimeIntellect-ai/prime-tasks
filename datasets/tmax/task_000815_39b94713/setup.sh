#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/research_data.db <<EOF
CREATE TABLE categories (
    cat_id INTEGER PRIMARY KEY,
    name TEXT,
    parent_id INTEGER
);

CREATE TABLE files (
    file_id INTEGER PRIMARY KEY,
    filename TEXT,
    size_bytes INTEGER,
    cat_id INTEGER
);

INSERT INTO categories (cat_id, name, parent_id) VALUES 
(1, 'Science', NULL),
(2, 'Physics', 1),
(3, 'Biology', 1),
(4, 'Quantum', 2),
(5, 'Genetics', 3),
(6, 'EmptyCat', NULL);

INSERT INTO files (file_id, filename, size_bytes, cat_id) VALUES 
(1, 'phys_data.csv', 100, 2),
(2, 'quant_sim.bin', 450, 4),
(3, 'bio_samples.csv', 200, 3),
(4, 'gen_seq.fasta', 300, 5);
EOF

    chmod -R 777 /home/user
