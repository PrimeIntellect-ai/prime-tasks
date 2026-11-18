#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libsqlite3-dev sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    sqlite3 /home/user/metrics.db <<EOF
CREATE TABLE server_metrics (server_id TEXT, timestamp INTEGER, cpu_usage REAL);
INSERT INTO server_metrics VALUES ('server_A', 100, 10.0);
INSERT INTO server_metrics VALUES ('server_A', 101, 12.0);
INSERT INTO server_metrics VALUES ('server_A', 102, 11.0);
INSERT INTO server_metrics VALUES ('server_A', 103, 40.0);
INSERT INTO server_metrics VALUES ('server_A', 104, 15.0);
INSERT INTO server_metrics VALUES ('server_B', 100, 50.0);
EOF

    chmod -R 777 /home/user
