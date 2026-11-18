#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/backup_metadata.db <<EOF
CREATE TABLE backups (
    id TEXT PRIMARY KEY,
    parent_id TEXT,
    status TEXT
);

CREATE TABLE storage (
    backup_id TEXT PRIMARY KEY,
    tier TEXT
);

-- Chain A (Valid)
INSERT INTO backups VALUES ('A1', NULL, 'success');
INSERT INTO backups VALUES ('A2', 'A1', 'success');
INSERT INTO backups VALUES ('A3', 'A2', 'success');
INSERT INTO storage VALUES ('A1', 'hot');
INSERT INTO storage VALUES ('A2', 'hot');
INSERT INTO storage VALUES ('A3', 'warm');

-- Chain B (Anomaly: parent B2 is cold, child B3 is hot)
INSERT INTO backups VALUES ('B1', NULL, 'success');
INSERT INTO backups VALUES ('B2', 'B1', 'success');
INSERT INTO backups VALUES ('B3', 'B2', 'success');
INSERT INTO storage VALUES ('B1', 'warm');
INSERT INTO storage VALUES ('B2', 'cold');
INSERT INTO storage VALUES ('B3', 'hot');

-- Chain C (Anomaly but failed status, should be ignored)
INSERT INTO backups VALUES ('C1', NULL, 'success');
INSERT INTO backups VALUES ('C2', 'C1', 'success');
INSERT INTO backups VALUES ('C3', 'C2', 'failed');
INSERT INTO storage VALUES ('C1', 'cold');
INSERT INTO storage VALUES ('C2', 'cold');
INSERT INTO storage VALUES ('C3', 'hot');

-- Chain D (Anomaly: parent D1 is cold, child D2 is hot)
INSERT INTO backups VALUES ('D1', NULL, 'success');
INSERT INTO backups VALUES ('D2', 'D1', 'success');
INSERT INTO storage VALUES ('D1', 'cold');
INSERT INTO storage VALUES ('D2', 'hot');
EOF

    chmod -R 777 /home/user
