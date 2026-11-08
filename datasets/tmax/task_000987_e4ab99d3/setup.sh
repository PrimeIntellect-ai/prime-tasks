#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak sqlite3
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Generate audio alert
    espeak -w /app/incident_alert.wav "Alert. System index corruption detected. Reject all ETL payloads containing transaction timestamps strictly older than one six eight five zero zero zero zero zero zero."

    # Create and populate warehouse.db
    sqlite3 /app/warehouse.db <<EOF
CREATE TABLE users (user_id TEXT, name TEXT);
CREATE TABLE transactions (tx_id TEXT, source_user TEXT, target_user TEXT, timestamp INTEGER);

INSERT INTO users VALUES ('user_739', 'Alice');
INSERT INTO users VALUES ('user_102', 'Bob');
INSERT INTO users VALUES ('user_884', 'Charlie');
INSERT INTO users VALUES ('user_999', 'Dave');

-- Valid transactions (timestamp >= 1685000000)
INSERT INTO transactions VALUES ('t1', 'user_102', 'user_739', 1685000001);
INSERT INTO transactions VALUES ('t2', 'user_884', 'user_739', 1685000002);
INSERT INTO transactions VALUES ('t3', 'user_999', 'user_739', 1685000003);
INSERT INTO transactions VALUES ('t4', 'user_102', 'user_739', 1685000004);
INSERT INTO transactions VALUES ('t5', 'user_884', 'user_739', 1685000005);

INSERT INTO transactions VALUES ('t6', 'user_739', 'user_102', 1685000006);
INSERT INTO transactions VALUES ('t7', 'user_884', 'user_102', 1685000007);
INSERT INTO transactions VALUES ('t8', 'user_999', 'user_102', 1685000008);
INSERT INTO transactions VALUES ('t9', 'user_739', 'user_102', 1685000009);

INSERT INTO transactions VALUES ('t10', 'user_739', 'user_884', 1685000010);
INSERT INTO transactions VALUES ('t11', 'user_102', 'user_884', 1685000011);
INSERT INTO transactions VALUES ('t12', 'user_999', 'user_884', 1685000012);

INSERT INTO transactions VALUES ('t13', 'user_739', 'user_999', 1685000013);

-- Stale transactions (timestamp < 1685000000)
INSERT INTO transactions VALUES ('s1', 'user_739', 'user_999', 1684000000);
INSERT INTO transactions VALUES ('s2', 'user_102', 'user_999', 1684000000);
INSERT INTO transactions VALUES ('s3', 'user_884', 'user_999', 1684000000);
INSERT INTO transactions VALUES ('s4', 'user_739', 'user_999', 1684000000);
INSERT INTO transactions VALUES ('s5', 'user_102', 'user_999', 1684000000);
INSERT INTO transactions VALUES ('s6', 'user_884', 'user_999', 1684000000);
INSERT INTO transactions VALUES ('s7', 'user_739', 'user_999', 1684000000);
EOF

    # Create clean corpus
    cat <<EOF > /app/corpus/clean/tx1.json
{"tx_id": "tx1", "timestamp": 1685000005, "source_user": "user_1", "target_user": "user_2"}
EOF
    cat <<EOF > /app/corpus/clean/tx2.json
{"tx_id": "tx2", "timestamp": 1685000000, "source_user": "user_3", "target_user": "user_4"}
EOF

    # Create evil corpus
    cat <<EOF > /app/corpus/evil/tx3.json
{"tx_id": "tx3", "timestamp": 1684999999, "source_user": "user_1", "target_user": "user_2"}
EOF
    cat <<EOF > /app/corpus/evil/tx4.json
{"tx_id": "tx4", "timestamp": 1680000000, "source_user": "user_3", "target_user": "user_4"}
EOF
    cat <<EOF > /app/corpus/evil/tx5_malformed.json
{"tx_id": "tx5", "timestamp": 1686000000, "source_user": "user_1",
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
