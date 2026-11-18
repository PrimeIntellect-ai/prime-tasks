#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user/data

    # Create mock data files
    echo "Raw Data D content." > /home/user/data/raw_d.txt
    echo "Raw Data E content." > /home/user/data/raw_e.txt
    echo "Raw Data F content." > /home/user/data/raw_f.txt
    echo "Intermediate content." > /home/user/data/int_b.txt
    echo "Intermediate content." > /home/user/data/int_c.txt
    echo "Final content." > /home/user/data/final_a.txt

    # Create SQLite DB
    cat << 'EOF' | sqlite3 /home/user/research.db
CREATE TABLE datasets (id INTEGER PRIMARY KEY, name TEXT UNIQUE, file_path TEXT);
CREATE TABLE dependencies (source_id INTEGER, derived_id INTEGER);

INSERT INTO datasets (id, name, file_path) VALUES 
(1, 'Final_Analysis_V3', '/home/user/data/final_a.txt'),
(2, 'Cleaned_Subset_B', '/home/user/data/int_b.txt'),
(3, 'Cleaned_Subset_C', '/home/user/data/int_c.txt'),
(4, 'Sensor_Data_D', '/home/user/data/raw_d.txt'),
(5, 'Sensor_Data_E', '/home/user/data/raw_e.txt'),
(6, 'Sensor_Data_F', '/home/user/data/raw_f.txt');

-- Final_Analysis_V3 (1) depends on B (2) and C (3)
INSERT INTO dependencies (source_id, derived_id) VALUES (2, 1);
INSERT INTO dependencies (source_id, derived_id) VALUES (3, 1);

-- Cleaned_Subset_B (2) depends on D (4) and E (5)
INSERT INTO dependencies (source_id, derived_id) VALUES (4, 2);
INSERT INTO dependencies (source_id, derived_id) VALUES (5, 2);

-- Cleaned_Subset_C (3) depends on E (5) and F (6)
INSERT INTO dependencies (source_id, derived_id) VALUES (5, 3);
INSERT INTO dependencies (source_id, derived_id) VALUES (6, 3);
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
