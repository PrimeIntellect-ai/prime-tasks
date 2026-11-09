#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 g++
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup_db.sql
CREATE TABLE task_runs (run_id INTEGER, task_id INTEGER, depends_on INTEGER, execution_time DATETIME);
INSERT INTO task_runs VALUES (1, 10, 20, '2023-01-01 10:00:00');
INSERT INTO task_runs VALUES (2, 20, 30, '2023-01-01 10:05:00');
INSERT INTO task_runs VALUES (3, 30, NULL, '2023-01-01 10:10:00');
INSERT INTO task_runs VALUES (4, 40, 50, '2023-01-01 10:15:00');
INSERT INTO task_runs VALUES (5, 50, 10, '2023-01-01 10:20:00');

-- Later runs update dependencies
INSERT INTO task_runs VALUES (6, 30, 40, '2023-01-02 10:10:00'); -- Creates cycle: 10->20->30->40->50->10
INSERT INTO task_runs VALUES (7, 60, 10, '2023-01-02 11:00:00'); 
INSERT INTO task_runs VALUES (8, 70, NULL, '2023-01-02 11:00:00');
EOF

    sqlite3 /home/user/etl.db < /tmp/setup_db.sql

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
