#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > setup_db.sql
CREATE TABLE jobs (job_id INTEGER PRIMARY KEY, job_name TEXT);
CREATE TABLE dependencies (job_id INTEGER, depends_on_job_id INTEGER);
CREATE TABLE executions (execution_id INTEGER PRIMARY KEY, job_id INTEGER, start_time DATETIME, end_time DATETIME, status TEXT);

-- Insert Jobs
INSERT INTO jobs VALUES (1, 'Extract_Sales');
INSERT INTO jobs VALUES (2, 'Extract_Users');
INSERT INTO jobs VALUES (3, 'Transform_Sales');
INSERT INTO jobs VALUES (4, 'Transform_Users');
INSERT INTO jobs VALUES (5, 'Load_DW');

-- Cyclic Jobs
INSERT INTO jobs VALUES (6, 'Update_Metrics_A');
INSERT INTO jobs VALUES (7, 'Update_Metrics_B');
INSERT INTO jobs VALUES (8, 'Update_Metrics_C');

-- Valid Dependencies
INSERT INTO dependencies VALUES (3, 1); -- Transform_Sales depends on Extract_Sales
INSERT INTO dependencies VALUES (4, 2); -- Transform_Users depends on Extract_Users
INSERT INTO dependencies VALUES (5, 3); -- Load_DW depends on Transform_Sales
INSERT INTO dependencies VALUES (5, 4); -- Load_DW depends on Transform_Users

-- Cyclic Dependencies (6 -> 7 -> 8 -> 6)
INSERT INTO dependencies VALUES (7, 6);
INSERT INTO dependencies VALUES (8, 7);
INSERT INTO dependencies VALUES (6, 8);

-- Executions (Extract_Sales)
INSERT INTO executions VALUES (1, 1, '2023-10-01 10:00:00', '2023-10-01 10:05:00', 'SUCCESS'); -- 300s
INSERT INTO executions VALUES (2, 1, '2023-10-02 10:00:00', '2023-10-02 10:05:10', 'SUCCESS'); -- 310s
INSERT INTO executions VALUES (3, 1, '2023-10-03 10:00:00', '2023-10-03 10:04:50', 'SUCCESS'); -- 290s
INSERT INTO executions VALUES (4, 1, '2023-10-04 10:00:00', '2023-10-04 10:05:00', 'FAILED');  -- should ignore
INSERT INTO executions VALUES (5, 1, '2023-10-05 10:00:00', '2023-10-05 10:06:40', 'SUCCESS'); -- 400s

-- Executions (Extract_Users)
INSERT INTO executions VALUES (6, 2, '2023-10-01 10:00:00', '2023-10-01 10:01:00', 'SUCCESS'); -- 60s
INSERT INTO executions VALUES (7, 2, '2023-10-02 10:00:00', '2023-10-02 10:02:00', 'SUCCESS'); -- 120s

-- Executions (Transform_Sales)

-- Executions (Transform_Users)
INSERT INTO executions VALUES (8, 4, '2023-10-01 10:05:00', '2023-10-01 10:10:00', 'SUCCESS'); -- 300s

-- Executions (Load_DW)
INSERT INTO executions VALUES (9, 5, '2023-10-01 10:15:00', '2023-10-01 10:20:00', 'SUCCESS'); -- 300s
INSERT INTO executions VALUES (10, 5, '2023-10-02 10:15:00', '2023-10-02 10:25:00', 'SUCCESS'); -- 600s
EOF

    sqlite3 /home/user/etl_metadata.db < setup_db.sql
    rm setup_db.sql

    chmod -R 777 /home/user
