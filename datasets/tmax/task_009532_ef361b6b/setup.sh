#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/backups.db <<EOF
CREATE TABLE servers (server_name TEXT PRIMARY KEY, region TEXT);
CREATE TABLE backups (id INTEGER PRIMARY KEY, server_name TEXT);
CREATE TABLE backup_metadata (backup_id INTEGER, status TEXT);

INSERT INTO servers VALUES ('db-prod-1', 'us-east-1');
INSERT INTO servers VALUES ('db-prod-2', 'eu-west-1');
INSERT INTO servers VALUES ('db-prod-3', 'us-east-1');

INSERT INTO backups VALUES (101, 'db-prod-1');
INSERT INTO backups VALUES (102, 'db-prod-2');
INSERT INTO backups VALUES (103, 'db-prod-1');
INSERT INTO backups VALUES (104, 'db-prod-3');

INSERT INTO backup_metadata VALUES (101, 'SUCCESS');
INSERT INTO backup_metadata VALUES (102, 'SUCCESS');
INSERT INTO backup_metadata VALUES (103, 'FAILED');
INSERT INTO backup_metadata VALUES (104, 'SUCCESS');
EOF

    cat << 'EOF' > /home/user/backup_logs.json
[
  {"backup_id": 101, "chunks": [{"size": 500}, {"size": 750}]},
  {"backup_id": 102, "chunks": [{"size": 2000}]},
  {"backup_id": 103, "chunks": [{"size": 100}]},
  {"backup_id": 104, "chunks": [{"size": 1000}, {"size": 250}]}
]
EOF

    cat << 'EOF' > /home/user/validate_backups.sh
#!/bin/bash
# Broken query with implicit cross join
QUERY="SELECT m.backup_id FROM backups b, servers s, backup_metadata m WHERE m.status = 'SUCCESS' AND s.region = 'us-east-1';"
IDS=$(sqlite3 /home/user/backups.db "$QUERY")

# TODO: Add jq pipeline to sum sizes for these IDS from /home/user/backup_logs.json
# and write the single integer to /home/user/final_size.txt
EOF
    chmod +x /home/user/validate_backups.sh

    chmod -R 777 /home/user
