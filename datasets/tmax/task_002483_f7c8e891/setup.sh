#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/access_logs.db << 'EOF'
CREATE TABLE employees (
    uid INTEGER PRIMARY KEY,
    full_name TEXT,
    department TEXT
);

CREATE TABLE facility_zones (
    zid INTEGER PRIMARY KEY,
    name TEXT,
    clearance_level INTEGER
);

CREATE TABLE event_log (
    event_id INTEGER PRIMARY KEY,
    person_ref INTEGER,
    area_ref INTEGER,
    event_time DATETIME,
    status TEXT
);

INSERT INTO employees (uid, full_name, department) VALUES
(101, 'Alice Smith', 'Engineering'),
(102, 'Bob Jones', 'HR'),
(103, 'Charlie Brown', 'Engineering'),
(104, 'Diana Prince', 'Engineering'),
(105, 'Evan Wright', 'Security');

INSERT INTO facility_zones (zid, name, clearance_level) VALUES
(10, 'Lobby', 1),
(11, 'Server Room A', 4),
(12, 'Server Room B', 5),
(13, 'Break Room', 2);

INSERT INTO event_log (event_id, person_ref, area_ref, event_time, status) VALUES
(1001, 101, 11, '2023-10-01 14:00:00', 'GRANT'),
(1002, 103, 11, '2023-10-01 23:15:00', 'GRANT'),
(1003, 102, 12, '2023-10-02 01:00:00', 'GRANT'),
(1004, 104, 12, '2023-10-02 02:30:00', 'GRANT'),
(1005, 101, 11, '2023-10-02 03:45:00', 'DENY'),
(1006, 104, 10, '2023-10-02 04:00:00', 'GRANT'),
(1007, 101, 12, '2023-10-02 04:55:00', 'GRANT');
EOF

    chmod -R 777 /home/user
