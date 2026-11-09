#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/financials.db <<EOF
CREATE TABLE transfers (id INTEGER PRIMARY KEY, source TEXT, target TEXT, amount REAL);
INSERT INTO transfers VALUES
(1, 'ACC1', 'ACC2', 100.0),
(2, 'ACC2', 'ACC3', 150.0),
(3, 'ACC3', 'ACC4', 200.0),
(4, 'ACC1', 'ACC5', 500.0),
(5, 'ACC5', 'ACC6', 50.0),
(6, 'ACC6', 'ACC7', 10.0),
(7, 'ACC3', 'ACC8', 300.0),
(8, 'ACC9', 'ACC10', 999.0);
EOF

    chmod -R 777 /home/user
