#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create the database and insert initial data
    cat << 'EOF' | sqlite3 /home/user/research_data.db
CREATE TABLE regions (
    region_id INTEGER PRIMARY KEY,
    name TEXT,
    climate_zone TEXT
);

CREATE TABLE plants (
    plant_id INTEGER PRIMARY KEY,
    species TEXT,
    region_id INTEGER,
    FOREIGN KEY(region_id) REFERENCES regions(region_id)
);

CREATE TABLE measurements (
    measurement_id INTEGER PRIMARY KEY,
    plant_id INTEGER,
    date TEXT,
    height_cm INTEGER,
    health_score INTEGER,
    FOREIGN KEY(plant_id) REFERENCES plants(plant_id)
);

-- Insert Data
INSERT INTO regions (region_id, name, climate_zone) VALUES 
(1, 'North Site', 'Temperate'),
(2, 'South Site', 'Tropical');

INSERT INTO plants (plant_id, species, region_id) VALUES 
(1, 'Oak', 1),
(2, 'Pine', 1),
(3, 'Palm', 2);

-- Oak (Temperate)
INSERT INTO measurements (plant_id, date, height_cm, health_score) VALUES
(1, '2023-01-01', 10, 8),
(1, '2023-01-02', 12, 9),
(1, '2023-01-03', 15, 10);

-- Pine (Temperate)
INSERT INTO measurements (plant_id, date, height_cm, health_score) VALUES
(2, '2023-01-01', 20, 5),
(2, '2023-01-02', 25, 6),
(2, '2023-01-03', 26, 7);

-- Palm (Tropical)
INSERT INTO measurements (plant_id, date, height_cm, health_score) VALUES
(3, '2023-01-01', 30, 10),
(3, '2023-01-02', 34, 9),
(3, '2023-01-03', 40, 8),
(3, '2023-01-04', 41, 7);
EOF

    chmod -R 777 /home/user
