#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 golang-go
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.sql
CREATE TABLE readings (ts INTEGER, sensor_id TEXT, value REAL);
INSERT INTO readings VALUES
(100, 'S1', 10.0),
(100, 'S1', 10.0),
(105, 'S1', 20.0),
(110, 'S1', 30.0),
(110, 'S1', 30.0),
(100, 'S2', 15.0),
(102, 'S2', 25.0),
(102, 'S2', 25.0);
EOF

    sqlite3 /home/user/warehouse.db < /tmp/setup.sql

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
