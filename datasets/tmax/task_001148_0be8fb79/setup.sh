#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/company.db <<EOF
CREATE TABLE org_chart (emp_id INTEGER PRIMARY KEY, manager_id INTEGER);
CREATE TABLE events (event_id INTEGER PRIMARY KEY, emp_id INTEGER, payload TEXT);

INSERT INTO org_chart (emp_id, manager_id) VALUES 
(100, NULL),
(1, 100),
(2, 1),
(3, 1),
(4, 2),
(5, 2),
(6, 3),
(7, 100);

INSERT INTO events (event_id, emp_id, payload) VALUES
(1, 4, '{"type": "sale", "amount": 100, "timestamp": "2023-10-01T10:00:00"}'),
(2, 4, '{"type": "lead", "amount": 0, "timestamp": "2023-10-01T11:00:00"}'),
(3, 4, '{"type": "sale", "amount": 150, "timestamp": "2023-10-02T10:00:00"}'),
(4, 5, '{"type": "sale", "amount": 200, "timestamp": "2023-10-01T09:00:00"}'),
(5, 5, '{"type": "sale", "amount": 300, "timestamp": "2023-10-03T09:00:00"}'),
(6, 1, '{"type": "sale", "amount": 500, "timestamp": "2023-10-01T08:00:00"}'),
(7, 7, '{"type": "sale", "amount": 999, "timestamp": "2023-10-01T08:00:00"}'),
(8, 2, '{"type": "sale", "amount": 50, "timestamp": "2023-10-05T08:00:00"}');
EOF

    chmod -R 777 /home/user
