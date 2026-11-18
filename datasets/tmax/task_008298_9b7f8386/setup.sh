#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/metadata.db <<EOF
CREATE TABLE categories (
    id INTEGER PRIMARY KEY,
    parent_id INTEGER,
    name TEXT,
    FOREIGN KEY(parent_id) REFERENCES categories(id)
);

CREATE TABLE datasets (
    id INTEGER PRIMARY KEY,
    category_id INTEGER,
    title TEXT,
    FOREIGN KEY(category_id) REFERENCES categories(id)
);

CREATE TABLE authors (
    id INTEGER PRIMARY KEY,
    dataset_id INTEGER,
    author TEXT,
    FOREIGN KEY(dataset_id) REFERENCES datasets(id)
);

INSERT INTO categories (id, parent_id, name) VALUES 
(1, NULL, 'Biology'),
(2, 1, 'Genomics'),
(3, 2, 'Transcriptomics'),
(4, 3, 'Single-Cell Transcriptomics'),
(5, 1, 'Proteomics'),
(6, NULL, 'Physics');

INSERT INTO datasets (id, category_id, title) VALUES 
(1, 2, 'Human Genome v38'),
(2, 3, 'Mouse RNA-Seq Timecourse'),
(3, 4, 'PBMC 10k Cells'),
(4, 5, 'Yeast Mass Spec'),
(5, 6, 'LHC Collision Event 90210');

INSERT INTO authors (id, dataset_id, author) VALUES 
(1, 1, 'Alice Smith'),
(2, 1, 'Bob Jones'),
(3, 2, 'Charlie Brown'),
(4, 3, 'Diana Prince'),
(5, 4, 'Eve Polastri'),
(6, 5, 'Frank Castle');
EOF

    chmod -R 777 /home/user
