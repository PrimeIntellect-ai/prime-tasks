#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > setup.sql
CREATE TABLE tasks (
    id INTEGER PRIMARY KEY,
    parent_id INTEGER,
    name TEXT,
    duration INTEGER
);

INSERT INTO tasks (id, parent_id, name, duration) VALUES
(1, NULL, 'Project A', 10),
(2, 1, 'Task A1', 5),
(3, 1, 'Task A2', 8),
(4, 2, 'Subtask A1.1', 3),
(5, 2, 'Subtask A1.2', 7),
(6, NULL, 'Project B', 15),
(7, 6, 'Task B1', 4),
(8, 7, 'Subtask B1.1', 6),
(9, 6, 'Task B2', 5),
(10, 3, 'Subtask A2.1', 2);
EOF

    sqlite3 tasks.db < setup.sql
    rm setup.sql

    chmod -R 777 /home/user
