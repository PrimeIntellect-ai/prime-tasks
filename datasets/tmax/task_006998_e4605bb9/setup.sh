#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sqlite3
pip3 install pytest pydantic

useradd -m -s /bin/bash user || true

sqlite3 /home/user/financial_logs.db <<EOF
CREATE TABLE ledger (tx_id TEXT, account_id TEXT, ts INTEGER, amount REAL);

-- Account A: Normal
INSERT INTO ledger VALUES ('tx_a1', 'A', 10000, 100.0);
INSERT INTO ledger VALUES ('tx_a2', 'A', 11000, -50.0);

-- Account B: Negative Balance
INSERT INTO ledger VALUES ('tx_b1', 'B', 10000, 50.0);
INSERT INTO ledger VALUES ('tx_b2', 'B', 12000, -100.0); -- trigger negative
INSERT INTO ledger VALUES ('tx_b3', 'B', 13000, 200.0);

-- Account C: Rapid Transactions (4 tx within 3600 sec)
INSERT INTO ledger VALUES ('tx_c1', 'C', 10000, 10.0);
INSERT INTO ledger VALUES ('tx_c2', 'C', 11000, 10.0);
INSERT INTO ledger VALUES ('tx_c3', 'C', 12000, 10.0);
INSERT INTO ledger VALUES ('tx_c4', 'C', 13000, 10.0); -- trigger rapid (13000-10000 = 3000 < 3600)
INSERT INTO ledger VALUES ('tx_c5', 'C', 20000, -5.0);

-- Account D: Both (Negative Balance earlier)
INSERT INTO ledger VALUES ('tx_d1', 'D', 10000, 10.0);
INSERT INTO ledger VALUES ('tx_d2', 'D', 10100, -20.0); -- trigger negative
INSERT INTO ledger VALUES ('tx_d3', 'D', 10200, 10.0);
INSERT INTO ledger VALUES ('tx_d4', 'D', 10300, 10.0); -- trigger rapid
EOF

chmod -R 777 /home/user
