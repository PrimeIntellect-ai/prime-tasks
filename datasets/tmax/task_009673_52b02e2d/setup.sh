#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 rustc cargo build-essential curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    sqlite3 /home/user/data/telemetry.db <<EOF
CREATE TABLE devices (id TEXT PRIMARY KEY, firmware_version TEXT, region TEXT);
CREATE TABLE logs (id INTEGER PRIMARY KEY, device_id TEXT, payload TEXT);

INSERT INTO devices (id, firmware_version, region) VALUES 
('dev1', '1.0', 'North'),
('dev2', '1.1', 'South'),
('dev3', '1.0', 'East'),
('dev4', '1.2', 'West'),
('dev5', '1.0', 'North');

INSERT INTO logs (device_id, payload) VALUES 
('dev1', '{"timestamp": 1, "sensor_readings": [{"type": "temperature", "value": 18.5}, {"type": "humidity", "value": 60.0}]}'),
('dev1', '{"timestamp": 2, "sensor_readings": [{"type": "temperature", "value": 19.2}]}'),
('dev2', '{"timestamp": 3, "sensor_readings": [{"type": "temperature", "value": 30.1}]}'),
('dev3', '{"timestamp": 4, "sensor_readings": [{"type": "temperature", "value": 22.0}, {"type": "pressure", "value": 1012}]}'),
('dev4', '{"timestamp": 5, "sensor_readings": [{"type": "temperature", "value": 25.5}]}'),
('dev5', '{"timestamp": 6, "sensor_readings": [{"type": "temperature", "value": 20.0}]}');
EOF

    chmod -R 777 /home/user
