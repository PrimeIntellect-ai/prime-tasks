#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    apt-get install -y sqlite3 libsqlite3-dev build-essential

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/research.db <<EOF
CREATE TABLE files (file_id INTEGER PRIMARY KEY, file_name TEXT, parent_id INTEGER, file_size INTEGER);
INSERT INTO files VALUES
(1, 'dataset_A', NULL, 100),
(2, 'dataset_A1', 1, 50),
(3, 'dataset_A2', 1, 200),
(4, 'dataset_A1a', 2, 30),
(5, 'dataset_A1b', 2, 20),
(6, 'dataset_A2a', 3, 10),
(7, 'dataset_B', NULL, 500),
(8, 'dataset_A1a1', 4, 5);
EOF

    chmod -R 777 /home/user
