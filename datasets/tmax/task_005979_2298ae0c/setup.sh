#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user

    sqlite3 /home/user/db_state.sqlite <<EOF
CREATE TABLE transactions (tx_id TEXT PRIMARY KEY, type TEXT);
CREATE TABLE locks (tx_id TEXT, resource_id TEXT, granted INTEGER);

INSERT INTO transactions (tx_id, type) VALUES 
('TX_A', 'app'), ('TX_B', 'app'), ('TX_C', 'app'), ('TX_D', 'backup'), ('TX_E', 'app'), ('TX_F', 'app');

-- TX_A holds RES_1, waits for RES_2
INSERT INTO locks (tx_id, resource_id, granted) VALUES ('TX_A', 'RES_1', 1);
INSERT INTO locks (tx_id, resource_id, granted) VALUES ('TX_A', 'RES_2', 0);

-- TX_B holds RES_2, waits for RES_3
INSERT INTO locks (tx_id, resource_id, granted) VALUES ('TX_B', 'RES_2', 1);
INSERT INTO locks (tx_id, resource_id, granted) VALUES ('TX_B', 'RES_3', 0);

-- TX_C holds RES_3, waits for RES_4
INSERT INTO locks (tx_id, resource_id, granted) VALUES ('TX_C', 'RES_3', 1);
INSERT INTO locks (tx_id, resource_id, granted) VALUES ('TX_C', 'RES_4', 0);

-- TX_D holds RES_4, waits for RES_1 (This creates the cycle: A -> B -> C -> D -> A)
INSERT INTO locks (tx_id, resource_id, granted) VALUES ('TX_D', 'RES_4', 1);
INSERT INTO locks (tx_id, resource_id, granted) VALUES ('TX_D', 'RES_1', 0);

-- Noise: TX_E holds RES_5, waits for RES_6. TX_F holds RES_6, no waits.
INSERT INTO locks (tx_id, resource_id, granted) VALUES ('TX_E', 'RES_5', 1);
INSERT INTO locks (tx_id, resource_id, granted) VALUES ('TX_E', 'RES_6', 0);
INSERT INTO locks (tx_id, resource_id, granted) VALUES ('TX_F', 'RES_6', 1);
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
