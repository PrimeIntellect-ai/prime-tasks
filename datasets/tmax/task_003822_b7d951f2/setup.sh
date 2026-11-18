#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # Create SQLite database with active and stale (is_active=0) routes
    sqlite3 routing.db <<EOF
CREATE TABLE network_links (source TEXT, target TEXT, latency INTEGER, is_active INTEGER);

-- Active optimal path: START -> N1 -> N2 -> END (Total Latency: 6)
INSERT INTO network_links VALUES ('START', 'N1', 2, 1);
INSERT INTO network_links VALUES ('N1', 'N2', 1, 1);
INSERT INTO network_links VALUES ('N2', 'END', 3, 1);

-- Active suboptimal path: START -> END (Total Latency: 10)
INSERT INTO network_links VALUES ('START', 'END', 10, 1);
INSERT INTO network_links VALUES ('START', 'N2', 8, 1);

-- Stale/Inactive paths (would create shorter paths if incorrectly included)
INSERT INTO network_links VALUES ('START', 'N1', 1, 0);
INSERT INTO network_links VALUES ('N1', 'END', 2, 0);

-- Duplicate active rows to test DISTINCT
INSERT INTO network_links VALUES ('START', 'N1', 2, 1);
INSERT INTO network_links VALUES ('N2', 'END', 3, 1);
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
