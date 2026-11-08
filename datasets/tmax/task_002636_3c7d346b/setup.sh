#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 cargo rustc libsqlite3-dev pkg-config
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Setup the database
    sqlite3 /home/user/research.db <<EOF
CREATE TABLE papers (id INTEGER PRIMARY KEY, title TEXT, year INTEGER, score REAL);
CREATE TABLE citations (source_id INTEGER, target_id INTEGER);

INSERT INTO papers (id, title, year, score) VALUES 
(1, 'Origin Paper', 2020, 10.5),
(2, 'Second Paper', 2020, 12.0),
(3, 'Third Paper', 2021, 8.0),
(4, 'Shortcut Paper', 2021, 9.5),
(5, 'Target Paper', 2022, 15.0),
(6, 'Noise Paper', 2020, 15.0);

INSERT INTO citations (source_id, target_id) VALUES
(1, 2),
(2, 3),
(3, 5),
(1, 4),
(4, 5);
EOF

    chmod -R 777 /home/user
