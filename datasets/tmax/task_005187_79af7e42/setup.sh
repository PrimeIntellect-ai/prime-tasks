#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/audit.db <<EOF
CREATE TABLE nodes (id VARCHAR, type VARCHAR, risk_weight INTEGER);
CREATE TABLE edges (src VARCHAR, dst VARCHAR, rel_type VARCHAR);

INSERT INTO nodes VALUES 
('U1', 'USER', 10),
('U2', 'USER', 20),
('U3', 'USER', 15),
('U4', 'USER', 25),
('R1', 'ROLE', 50),
('R2', 'ROLE', 30),
('R3', 'ROLE', 40),
('R4', 'ROLE', 60);

-- Path 1: U1 -> R1 -> R2 -> U2 (Risk: 10 + 50 + 30 + 20 = 110)
INSERT INTO edges VALUES ('U1', 'R1', 'ASSUMES'), ('R1', 'R2', 'INHERITS'), ('R2', 'U2', 'CAN_MODIFY');

-- Path 2: U3 -> R3 -> R2 -> U2 (Risk: 15 + 40 + 30 + 20 = 105) (Target U2, lower risk)
INSERT INTO edges VALUES ('U3', 'R3', 'ASSUMES'), ('R3', 'R2', 'INHERITS');

-- Path 3: U3 -> R1 -> R4 -> U4 (Risk: 15 + 50 + 60 + 25 = 150)
INSERT INTO edges VALUES ('U3', 'R1', 'ASSUMES'), ('R1', 'R4', 'INHERITS'), ('R4', 'U4', 'CAN_MODIFY');

-- Path 4: U1 -> R1 -> R4 -> U4 (Risk: 10 + 50 + 60 + 25 = 145) (Target U4, lower risk)

-- Path 5 tie condition: U4 -> R3 -> R4 -> U1 (Risk: 25 + 40 + 60 + 10 = 135)
-- Path 6 tie condition: U2 -> R1 -> R2 -> U1 (Risk: 20 + 50 + 30 + 10 = 110) wait no we want a tie.
-- Let's make Path 6 risk exactly 135. U2(20) + R?(45) + R4(60) + U1(10) = 135
INSERT INTO nodes VALUES ('R5', 'ROLE', 45);
INSERT INTO edges VALUES ('U4', 'R3', 'ASSUMES'), ('R3', 'R4', 'INHERITS'), ('R4', 'U1', 'CAN_MODIFY');
INSERT INTO edges VALUES ('U2', 'R5', 'ASSUMES'), ('R5', 'R4', 'INHERITS');

-- Self loop (should be filtered out)
INSERT INTO edges VALUES ('U2', 'R1', 'ASSUMES'), ('R2', 'U2', 'CAN_MODIFY');
EOF

    chmod -R 777 /home/user
