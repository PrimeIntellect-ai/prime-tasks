#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip cargo sqlite3 libsqlite3-dev pkg-config
pip3 install pytest

mkdir -p /home/user/audit
cd /home/user/audit
cargo init --bin

cat << 'EOF' > Cargo.toml
[package]
name = "audit"
version = "0.1.0"
edition = "2021"

[dependencies]
rusqlite = "0.29.0"
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
EOF

cat << 'EOF' > systems.json
[
  {"id": 10, "name": "PublicWeb"},
  {"id": 20, "name": "JumpBox"},
  {"id": 30, "name": "AppServer"},
  {"id": 40, "name": "DbMain"},
  {"id": 50, "name": "SecureVault"},
  {"id": 60, "name": "Isolated"}
]
EOF

sqlite3 access.db << 'EOF'
CREATE TABLE network_links (source_id INTEGER, target_id INTEGER, protocol TEXT);
INSERT INTO network_links VALUES (10, 20, 'SSH');
INSERT INTO network_links VALUES (10, 30, 'HTTP');
INSERT INTO network_links VALUES (20, 30, 'SSH');
INSERT INTO network_links VALUES (30, 40, 'SQL');
INSERT INTO network_links VALUES (20, 40, 'SSH');
INSERT INTO network_links VALUES (40, 50, 'SSH');
INSERT INTO network_links VALUES (30, 50, 'SSH');
INSERT INTO network_links VALUES (10, 60, 'SSH');
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
