#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/etl_metadata.db <<EOF
CREATE TABLE dependencies (source_task TEXT, target_task TEXT);
INSERT INTO dependencies VALUES
('Extract_API', 'Clean_Data'),
('Clean_Data', 'Transform_Users'),
('Transform_Users', 'Aggregate_Metrics'),
('Aggregate_Metrics', 'Load_DW'),
('Extract_API', 'Fast_Track'),
('Fast_Track', 'Load_DW'),
('Extract_API', 'Legacy_Path'),
('Legacy_Path', 'Middle_Step'),
('Middle_Step', 'Load_DW');

CREATE TABLE task_logs (task_id TEXT, start_time DATETIME, end_time DATETIME, status TEXT, run_id INTEGER);
INSERT INTO task_logs VALUES
('Extract_API', '2023-01-01 10:00:00', '2023-01-01 10:00:10', 'SUCCESS', 2),
('Extract_API', '2023-01-01 09:00:00', '2023-01-01 09:00:15', 'FAIL', 1),
('Fast_Track', '2023-01-01 10:01:00', '2023-01-01 10:01:04', 'SUCCESS', 2),
('Fast_Track', '2023-01-01 09:01:00', '2023-01-01 09:01:05', 'SUCCESS', 1),
('Load_DW', '2023-01-01 10:05:00', '2023-01-01 10:05:15', 'SUCCESS', 5),
('Load_DW', '2023-01-01 09:05:00', '2023-01-01 09:05:20', 'FAIL', 4);
EOF

    chmod -R 777 /home/user
