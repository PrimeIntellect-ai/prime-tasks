#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/datasets
    sqlite3 /home/user/datasets/sensors.db <<EOF
CREATE TABLE metadata (version TEXT);
INSERT INTO metadata VALUES ('2.4.1');

CREATE TABLE logs (log_id INTEGER PRIMARY KEY, msg TEXT);
INSERT INTO logs (msg) VALUES ('System started');

CREATE TABLE env_data_v7 (
    id INTEGER PRIMARY KEY,
    device_id TEXT,
    t_stamp DATETIME,
    temp_c REAL,
    humidity REAL
);

INSERT INTO env_data_v7 (device_id, t_stamp, temp_c, humidity) VALUES ('SENS-01', '2023-10-01T10:00:00Z', 18.5, 45.0);
INSERT INTO env_data_v7 (device_id, t_stamp, temp_c, humidity) VALUES ('SENS-02', '2023-10-01T11:00:00Z', 22.1, 46.0);
INSERT INTO env_data_v7 (device_id, t_stamp, temp_c, humidity) VALUES ('SENS-01', '2023-10-01T12:00:00Z', 25.4, 42.0);
INSERT INTO env_data_v7 (device_id, t_stamp, temp_c, humidity) VALUES ('SENS-03', '2023-10-01T13:00:00Z', 19.9, 50.0);
INSERT INTO env_data_v7 (device_id, t_stamp, temp_c, humidity) VALUES ('SENS-02', '2023-10-01T14:00:00Z', 21.0, 48.0);
INSERT INTO env_data_v7 (device_id, t_stamp, temp_c, humidity) VALUES ('SENS-01', '2023-10-01T15:00:00Z', 26.5, 40.0);
EOF

    chmod -R 777 /home/user
