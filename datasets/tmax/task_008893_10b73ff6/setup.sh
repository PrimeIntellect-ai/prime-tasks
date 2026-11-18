#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest rdflib

    mkdir -p /home/user

    cat << 'EOF' > /home/user/transactions.ttl
@prefix ex: <http://example.org/> .
@prefix tx: <http://example.org/tx/> .

tx:A001 ex:amount 15000 ; ex:transfersTo tx:B002 .
tx:B002 ex:amount 20000 ; ex:transfersTo tx:C003 .
tx:C003 ex:amount 18000 ; ex:transfersTo tx:A001 .

# Dummy cycle that is too small amount
tx:D004 ex:amount 500 ; ex:transfersTo tx:E005 .
tx:E005 ex:amount 600 ; ex:transfersTo tx:F006 .
tx:F006 ex:amount 700 ; ex:transfersTo tx:D004 .

# Not a cycle
tx:X001 ex:amount 50000 ; ex:transfersTo tx:Y002 .
tx:Y002 ex:amount 60000 ; ex:transfersTo tx:Z003 .
EOF

    sqlite3 /home/user/audit_logs.db << 'EOF'
CREATE TABLE users (id INTEGER PRIMARY KEY, username TEXT, department TEXT);
INSERT INTO users VALUES (1, 'alice_compliance', 'Compliance');
INSERT INTO users VALUES (2, 'bob_finance', 'Finance');
INSERT INTO users VALUES (3, 'charlie_admin', 'IT');

CREATE TABLE approvals (id INTEGER PRIMARY KEY, tx_id TEXT, user_id INTEGER, approved_at DATETIME);
INSERT INTO approvals VALUES (1, 'A001', 2, '2023-10-01 10:00:00');
INSERT INTO approvals VALUES (2, 'A001', 1, '2023-10-02 11:00:00');
INSERT INTO approvals VALUES (3, 'B002', 3, '2023-10-01 12:00:00');
INSERT INTO approvals VALUES (4, 'B002', 2, '2023-10-02 09:00:00');
INSERT INTO approvals VALUES (5, 'C003', 1, '2023-10-01 14:00:00');
INSERT INTO approvals VALUES (6, 'C003', 3, '2023-10-03 16:00:00');
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
