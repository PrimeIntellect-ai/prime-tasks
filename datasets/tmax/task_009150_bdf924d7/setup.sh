#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    sqlite3 /home/user/audit.db <<EOF
CREATE TABLE access_logs(user_id TEXT, resource_id TEXT, access_time INTEGER);

-- U1 will trigger the rule (6 events between 1000 and 1500)
INSERT INTO access_logs VALUES ('U1', 'R1', 1000);
INSERT INTO access_logs VALUES ('U1', 'R2', 1100);
INSERT INTO access_logs VALUES ('U1', 'R3', 1200);
INSERT INTO access_logs VALUES ('U1', 'R4', 1300);
INSERT INTO access_logs VALUES ('U1', 'R5', 1400);
INSERT INTO access_logs VALUES ('U1', 'R6', 1500);

-- U2 will NOT trigger the rule (spread out)
INSERT INTO access_logs VALUES ('U2', 'R1', 2000);
INSERT INTO access_logs VALUES ('U2', 'R2', 3000);
INSERT INTO access_logs VALUES ('U2', 'R3', 4000);

-- U3 will trigger the rule (7 events in exactly 600 seconds)
INSERT INTO access_logs VALUES ('U3', 'R1', 5000);
INSERT INTO access_logs VALUES ('U3', 'R2', 5100);
INSERT INTO access_logs VALUES ('U3', 'R3', 5200);
INSERT INTO access_logs VALUES ('U3', 'R4', 5300);
INSERT INTO access_logs VALUES ('U3', 'R5', 5400);
INSERT INTO access_logs VALUES ('U3', 'R6', 5500);
INSERT INTO access_logs VALUES ('U3', 'R7', 5600);

-- U4 will NOT trigger the rule (exactly 5 events in 600s)
INSERT INTO access_logs VALUES ('U4', 'R1', 6000);
INSERT INTO access_logs VALUES ('U4', 'R2', 6100);
INSERT INTO access_logs VALUES ('U4', 'R3', 6200);
INSERT INTO access_logs VALUES ('U4', 'R4', 6300);
INSERT INTO access_logs VALUES ('U4', 'R5', 6400);
EOF

    chown -R user:user /home/user/audit.db
    chmod -R 777 /home/user
