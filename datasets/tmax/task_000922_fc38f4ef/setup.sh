#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/audit.db <<EOF
CREATE TABLE system_access_logs(
    log_id INTEGER PRIMARY KEY,
    employee_id TEXT,
    action TEXT,
    event_time DATETIME
);

CREATE INDEX idx_stale_time ON system_access_logs(event_time);

INSERT INTO system_access_logs(employee_id, action, event_time) VALUES
('E001', 'GRANTED', '2023-10-15 08:00:00'),
('E001', 'DENIED', '2023-10-15 08:32:11'),
('E001', 'DENIED', '2023-10-15 08:15:00'),
('E002', 'DENIED', '2023-10-14 19:12:05'),
('E002', 'GRANTED', '2023-10-14 19:15:00'),
('E003', 'GRANTED', '2023-10-16 09:00:00'),
('E004', 'DENIED', '2023-10-12 11:11:11'),
('E004', 'DENIED', '2023-10-12 12:22:22');
EOF

    chmod -R 777 /home/user
