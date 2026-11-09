#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sqlite3 jq
pip3 install pytest

mkdir -p /home/user
cd /home/user

cat << 'EOF' > init.sql
CREATE TABLE filesystem (
    id INTEGER PRIMARY KEY,
    parent_id INTEGER,
    name TEXT,
    tenant_id INTEGER
);

CREATE INDEX idx_tenant_parent ON filesystem(tenant_id, parent_id);

-- Data for tenant 455
INSERT INTO filesystem (id, parent_id, name, tenant_id) VALUES 
(1, NULL, 'backup_root', 455),
(2, 1, 'etc', 455),
(3, 1, 'var', 455),
(4, 2, 'passwd', 455),
(5, 3, 'log', 455),
(6, 5, 'syslog', 455);

-- Data for tenant 999 (should not appear in tenant 455's output)
INSERT INTO filesystem (id, parent_id, name, tenant_id) VALUES 
(7, NULL, 'backup_root_999', 999),
(8, 7, 'bin', 999);
EOF

sqlite3 backup_meta.db < init.sql
rm init.sql

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
