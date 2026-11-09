#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    apt-get install -y sqlite3 libsqlite3-dev gcc

    mkdir -p /home/user/data
    mkdir -p /home/user/pipeline

    sqlite3 /home/user/data/legacy_telemetry.db <<EOF
CREATE TABLE raw_telemetry (
    record_id INTEGER PRIMARY KEY,
    device_uid TEXT NOT NULL,
    recorded_at INTEGER NOT NULL,
    val REAL NOT NULL
);

INSERT INTO raw_telemetry (device_uid, recorded_at, val) VALUES 
('DEV01', 1600000000, 10.0),
('DEV01', 1600000010, 20.0),
('DEV01', 1600000020, 30.0),
('DEV01', 1600000030, 80.0),
('DEV01', 1600000040, 90.0),
('DEV02', 1600000005, 55.0),
('DEV02', 1600000015, 60.0),
('DEV02', 1600000025, 30.0),
('DEV02', 1600000035, 70.0);
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
