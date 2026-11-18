#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev gcc make libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/finance_data.db <<EOF
CREATE TABLE nosql_store (
    doc_id TEXT PRIMARY KEY,
    document JSON
);

INSERT INTO nosql_store (doc_id, document) VALUES 
('tx_001', '{"type": "transaction", "details": {"src": "ACC_A", "dst": "ACC_B", "amt": 100}}'),
('tx_002', '{"type": "transaction", "details": {"src": "ACC_B", "dst": "ACC_C", "amt": 150}}'),
('tx_003', '{"type": "transaction", "details": {"src": "ACC_C", "dst": "ACC_A", "amt": 200}}'),

('tx_004', '{"type": "transaction", "details": {"src": "ACC_X", "dst": "ACC_Y", "amt": 50}}'),
('tx_005', '{"type": "transaction", "details": {"src": "ACC_Y", "dst": "ACC_Z", "amt": 60}}'),
('tx_006', '{"type": "transaction", "details": {"src": "ACC_Z", "dst": "ACC_X", "amt": 70}}'),

('tx_007', '{"type": "transaction", "details": {"src": "ACC_M", "dst": "ACC_N", "amt": 500}}'),
('tx_008', '{"type": "transaction", "details": {"src": "ACC_N", "dst": "ACC_O", "amt": 10}}');
EOF

    chmod -R 777 /home/user
