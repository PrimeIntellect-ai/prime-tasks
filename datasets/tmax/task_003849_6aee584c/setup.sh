#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > /home/user/setup_db.sql
CREATE TABLE datasets (id INTEGER PRIMARY KEY, name TEXT, size_mb INTEGER, domain TEXT);
CREATE TABLE dependencies (source_id INTEGER, target_id INTEGER);

-- Insert Nodes
INSERT INTO datasets (id, name, size_mb, domain) VALUES 
(1, 'Base_Sequences', 100, 'Genomics'),
(2, 'Aligned_Reads', 250, 'Genomics'),
(3, 'Variant_Calls', 300, 'Genomics'),
(4, 'Annotated_Variants', 150, 'Genomics'),
(5, 'Population_Frequencies', 800, 'Genomics'),
(6, 'Protein_Structures', 1200, 'Proteomics'),
(7, 'GWAS_Summary', 950, 'Genomics'),
(8, 'Expression_Profiles', 600, 'Genomics'),
(9, 'Clinical_Correlations', 1100, 'Genomics');

-- Insert Edges (source depends on target)
-- Path from Base_Sequences (1):
-- 2 depends on 1
INSERT INTO dependencies (source_id, target_id) VALUES (2, 1);
-- 3 depends on 2
INSERT INTO dependencies (source_id, target_id) VALUES (3, 2);
-- 4 depends on 3
INSERT INTO dependencies (source_id, target_id) VALUES (4, 3);
-- 5 depends on 4
INSERT INTO dependencies (source_id, target_id) VALUES (5, 4);
-- 6 depends on 4 (Proteomics - should be filtered out)
INSERT INTO dependencies (source_id, target_id) VALUES (6, 4);
-- 7 depends on 3
INSERT INTO dependencies (source_id, target_id) VALUES (7, 3);
-- 8 depends on 2
INSERT INTO dependencies (source_id, target_id) VALUES (8, 2);
-- 9 depends on 7
INSERT INTO dependencies (source_id, target_id) VALUES (9, 7);

EOF

    sqlite3 /home/user/datasets.db < /home/user/setup_db.sql
    rm /home/user/setup_db.sql

    chmod -R 777 /home/user
