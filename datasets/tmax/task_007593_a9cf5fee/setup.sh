#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 curl build-essential pkg-config libsqlite3-dev
    pip3 install pytest

    export RUSTUP_HOME=/usr/local/rustup
    export CARGO_HOME=/usr/local/cargo
    export PATH=/usr/local/cargo/bin:$PATH
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    chmod -R a+w $RUSTUP_HOME $CARGO_HOME

    mkdir -p /home/user

    cat << 'EOF' > /home/user/node_status.json
[
  {"id": "DB_MAIN_FULL", "state": "valid"},
  {"id": "INC_1", "state": "valid"},
  {"id": "INC_2", "state": "corrupted"},
  {"id": "INC_3", "state": "valid"},
  {"id": "RESTORE_COMPLETE", "state": "valid"},
  {"id": "FAST_TRACK", "state": "corrupted"}
]
EOF

    sqlite3 /home/user/backups.db <<EOF
CREATE TABLE recovery_edges (src TEXT, dst TEXT, time_mins INTEGER);
INSERT INTO recovery_edges VALUES ('DB_MAIN_FULL', 'INC_1', 10);
INSERT INTO recovery_edges VALUES ('DB_MAIN_FULL', 'INC_2', 5);
INSERT INTO recovery_edges VALUES ('INC_2', 'RESTORE_COMPLETE', 5);
INSERT INTO recovery_edges VALUES ('INC_1', 'INC_3', 15);
INSERT INTO recovery_edges VALUES ('INC_3', 'RESTORE_COMPLETE', 10);
INSERT INTO recovery_edges VALUES ('DB_MAIN_FULL', 'FAST_TRACK', 2);
INSERT INTO recovery_edges VALUES ('FAST_TRACK', 'RESTORE_COMPLETE', 2);
INSERT INTO recovery_edges VALUES ('DB_MAIN_FULL', 'RESTORE_COMPLETE', 60);
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
