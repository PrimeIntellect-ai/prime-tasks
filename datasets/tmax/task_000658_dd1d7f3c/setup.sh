#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/backups/raw_logs/db1
    mkdir -p /home/user/backups/raw_logs/db2/nested
    mkdir -p /home/user/backups/processed/chunks

    cat << 'EOF' > /home/user/backups/raw_logs/db1/log_a.wal
[2023-10-01T10:00:00] BEGIN TX 42
INSERT INTO settings (key, val) VALUES ('theme', 'dark');
[2023-10-01T10:00:01] COMMIT TX 42
[2023-10-01T10:05:00] BEGIN TX 45
UPDATE users SET status = 'banned' WHERE id = 9;
[2023-10-01T10:05:02] ROLLBACK TX 45
EOF

    cat << 'EOF' > /home/user/backups/raw_logs/db2/nested/log_b.wal
[2023-10-01T09:00:00] BEGIN TX 12
CREATE TABLE test (id INT);
INSERT INTO test VALUES (1);
INSERT INTO test VALUES (2);
[2023-10-01T09:00:05] COMMIT TX 12
[2023-10-01T11:00:00] BEGIN TX 88
DROP TABLE users;
[2023-10-01T11:00:01] ROLLBACK TX 88
EOF

    cat << 'EOF' > /home/user/backups/raw_logs/log_c.wal
[2023-10-01T10:30:00] BEGIN TX 60
ALTER TABLE items ADD COLUMN price INT;
[2023-10-01T10:30:02] COMMIT TX 60
EOF

    chown -R user:user /home/user/backups
    chmod -R 777 /home/user
