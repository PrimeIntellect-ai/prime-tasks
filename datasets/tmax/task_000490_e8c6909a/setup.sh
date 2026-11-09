#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # Create the SQLite DB
    sqlite3 datasets.db <<EOF
CREATE TABLE nodes (
    node_id INTEGER PRIMARY KEY,
    dataset_name TEXT NOT NULL
);

CREATE TABLE edges (
    dependent_id INTEGER,
    source_id INTEGER,
    FOREIGN KEY(dependent_id) REFERENCES nodes(node_id),
    FOREIGN KEY(source_id) REFERENCES nodes(node_id)
);

-- Insert datasets
INSERT INTO nodes (node_id, dataset_name) VALUES 
(1, 'ClimateData'),
(2, 'WeatherModels'),
(3, 'OceanTemps'),
(4, 'TidalPatterns'),
(5, 'AtmosphereLogs'),
(6, 'SolarRadiation');

-- Insert dependencies (dependent_id depends on source_id)
-- Deadlock 1: ClimateData (1) and WeatherModels (2)
INSERT INTO edges (dependent_id, source_id) VALUES (1, 2), (2, 1);

-- Deadlock 2: OceanTemps (3) and TidalPatterns (4)
INSERT INTO edges (dependent_id, source_id) VALUES (3, 4), (4, 3);

-- Other dependencies to calculate in-degree (how many depend ON this node)
-- Meaning: dependent_id depends on source_id. So in-degree of X is count(dependent_id) where source_id = X
INSERT INTO edges (dependent_id, source_id) VALUES 
(5, 1), -- AtmosphereLogs depends on ClimateData
(6, 1), -- SolarRadiation depends on ClimateData
(5, 2), -- AtmosphereLogs depends on WeatherModels
(1, 3), -- ClimateData depends on OceanTemps
(6, 4); -- SolarRadiation depends on TidalPatterns

EOF
    chmod 644 datasets.db

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
