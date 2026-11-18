#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user
    cd /home/user

    sqlite3 audit.db <<EOF
CREATE TABLE Entities (
    id INTEGER PRIMARY KEY,
    name VARCHAR,
    type VARCHAR,
    status VARCHAR
);

CREATE TABLE AccessGrants (
    source_id INTEGER,
    target_id INTEGER,
    status VARCHAR
);

INSERT INTO Entities (id, name, type, status) VALUES
(1, 'alice_admin', 'USER', 'REVOKED'),
(2, 'bob_dev', 'USER', 'ACTIVE'),
(3, 'charlie_ops', 'USER', 'REVOKED'),
(4, 'dev_group', 'GROUP', 'ACTIVE'),
(5, 'ops_group', 'GROUP', 'ACTIVE'),
(6, 'ci_cd_service', 'SERVICE_ACCOUNT', 'ACTIVE'),
(7, 'reporting_service', 'SERVICE_ACCOUNT', 'ACTIVE'),
(8, 'legacy_app', 'SERVICE_ACCOUNT', 'REVOKED'),
(9, 'CustomerData', 'DATA_LAKE', 'ACTIVE'),
(10, 'LedgerMain', 'FINANCE_DB', 'ACTIVE'),
(11, 'TempData', 'DATA_LAKE', 'ACTIVE');

-- Insert Edges
-- alice_admin -> dev_group (ACTIVE)
INSERT INTO AccessGrants (source_id, target_id, status) VALUES (1, 4, 'ACTIVE');
-- dev_group -> ci_cd_service (ACTIVE)
INSERT INTO AccessGrants (source_id, target_id, status) VALUES (4, 6, 'ACTIVE');
-- ci_cd_service -> LedgerMain (ACTIVE)  ==> Alice has path to LedgerMain in 3 hops
INSERT INTO AccessGrants (source_id, target_id, status) VALUES (6, 10, 'ACTIVE');

-- alice_admin -> reporting_service (ACTIVE)
INSERT INTO AccessGrants (source_id, target_id, status) VALUES (1, 7, 'ACTIVE');
-- reporting_service -> CustomerData (ACTIVE) ==> Alice has path to CustomerData in 2 hops
INSERT INTO AccessGrants (source_id, target_id, status) VALUES (7, 9, 'ACTIVE');

-- charlie_ops -> ops_group (ACTIVE)
INSERT INTO AccessGrants (source_id, target_id, status) VALUES (3, 5, 'ACTIVE');
-- ops_group -> TempData (ACTIVE) ==> Charlie has path to TempData in 2 hops
INSERT INTO AccessGrants (source_id, target_id, status) VALUES (5, 11, 'ACTIVE');

-- charlie_ops -> legacy_app (ACTIVE)
INSERT INTO AccessGrants (source_id, target_id, status) VALUES (3, 8, 'ACTIVE');
-- legacy_app -> CustomerData (ACTIVE) ==> Charlie has path to CustomerData in 2 hops
INSERT INTO AccessGrants (source_id, target_id, status) VALUES (8, 9, 'ACTIVE');
EOF

    chmod -R 777 /home/user
