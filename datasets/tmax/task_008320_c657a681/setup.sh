#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/etl_metadata.db <<EOF
CREATE TABLE jobs(id INTEGER PRIMARY KEY, target_table TEXT, sql_query TEXT);
INSERT INTO jobs (target_table, sql_query) VALUES ('stg_clicks', 'SELECT * FROM raw_clicks WHERE id IS NOT NULL');
INSERT INTO jobs (target_table, sql_query) VALUES ('filtered_clicks', 'SELECT * FROM stg_clicks WHERE valid = 1');
INSERT INTO jobs (target_table, sql_query) VALUES ('user_sessions', 'SELECT * FROM filtered_clicks JOIN user_dim ON filtered_clicks.u = user_dim.u');
INSERT INTO jobs (target_table, sql_query) VALUES ('daily_metrics', 'SELECT date, count(*) FROM user_sessions GROUP BY date');
INSERT INTO jobs (target_table, sql_query) VALUES ('realtime_metrics', 'SELECT * FROM stg_clicks JOIN speed_dim ON stg_clicks.id = speed_dim.id');
INSERT INTO jobs (target_table, sql_query) VALUES ('executive_dashboard', 'SELECT * FROM daily_metrics JOIN financial_dim ON daily_metrics.date = financial_dim.date');
INSERT INTO jobs (target_table, sql_query) VALUES ('executive_dashboard', 'SELECT * FROM realtime_metrics JOIN financial_dim ON realtime_metrics.date = financial_dim.date');
EOF

    chmod -R 777 /home/user
