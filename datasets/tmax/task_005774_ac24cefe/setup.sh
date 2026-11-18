#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 golang-go git
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    sqlite3 /home/user/lineage.db <<EOF
CREATE TABLE datasets (
    dataset_id INTEGER PRIMARY KEY,
    title TEXT,
    format TEXT
);

CREATE TABLE derivation_edges (
    source_id INTEGER,
    target_id INTEGER,
    operation TEXT,
    FOREIGN KEY(source_id) REFERENCES datasets(dataset_id),
    FOREIGN KEY(target_id) REFERENCES datasets(dataset_id)
);

INSERT INTO datasets (dataset_id, title, format) VALUES 
(1, 'Raw Sensor Data', 'csv'),
(2, 'Cleaned Sensor Data', 'parquet'),
(3, 'Aggregated Daily Data', 'json'),
(4, 'Anomaly Report', 'pdf'),
(5, 'User Logs', 'txt'),
(6, 'Parsed Logs', 'csv'),
(7, 'Joined Analytics', 'parquet');

INSERT INTO derivation_edges (source_id, target_id, operation) VALUES
(1, 2, 'clean'),
(2, 3, 'aggregate'),
(3, 4, 'detect_anomalies'),
(5, 6, 'parse'),
(3, 7, 'join'),
(6, 7, 'join');
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
