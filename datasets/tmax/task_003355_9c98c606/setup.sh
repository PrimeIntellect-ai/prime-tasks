#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install task dependencies
    apt-get install -y sqlite3 libsqlite3-dev g++

    # Create user
    useradd -m -s /bin/bash user || true

    # Create the database
    sqlite3 /home/user/research_data.db <<EOF
CREATE TABLE papers (id INTEGER PRIMARY KEY, title TEXT, year INTEGER);
CREATE TABLE citations (source_id INTEGER, target_id INTEGER);

INSERT INTO papers (id, title, year) VALUES 
(1, 'A', 2021), (2, 'B', 2021), (3, 'C', 2021),
(4, 'D', 2019), (5, 'E', 2022), (6, 'F', 2022),
(7, 'G', 2022), (8, 'H', 2023), (9, 'I', 2023),
(10, 'J', 2023);

-- Valid cycle: 1-2-3 (all >= 2020)
INSERT INTO citations (source_id, target_id) VALUES (1, 2), (2, 3), (3, 1);

-- Invalid cycle: 4-5-6 (Paper 4 is 2019)
INSERT INTO citations (source_id, target_id) VALUES (4, 5), (5, 6), (6, 4);

-- Valid cycle: 8-9-10 (all >= 2020)
INSERT INTO citations (source_id, target_id) VALUES (8, 9), (9, 10), (10, 8);

-- Valid cycle: 5-6-7 (all >= 2020)
INSERT INTO citations (source_id, target_id) VALUES (5, 6), (6, 7), (7, 5);

-- Noise
INSERT INTO citations (source_id, target_id) VALUES (1, 5), (2, 8), (10, 1);
EOF

    # Set permissions
    chmod -R 777 /home/user
