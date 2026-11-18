#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 cargo rustc libsqlite3-dev pkg-config
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cd /home/user

    sqlite3 raw_data.db <<EOF
CREATE TABLE raw_readings (
    sensor_id TEXT,
    sensor_model TEXT,
    location_name TEXT,
    latitude REAL,
    longitude REAL,
    timestamp INTEGER,
    temperature REAL,
    humidity REAL
);
INSERT INTO raw_readings VALUES ('S1', 'ModelX', 'Station_A', 40.7128, -74.0060, 1622505600, 22.5, 55.2);
INSERT INTO raw_readings VALUES ('S2', 'ModelY', 'Station_B', 34.0522, -118.2437, 1622505600, 28.1, 40.1);
INSERT INTO raw_readings VALUES ('S1', 'ModelX', 'Station_A', 40.7128, -74.0060, 1622509200, 23.0, 54.0);
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
