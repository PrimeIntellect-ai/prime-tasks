#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 espeak ffmpeg flac
    pip3 install pytest

    mkdir -p /app

    # Generate the audio file
    espeak -w /app/dictation.wav "Subject: Alice Johnson. Location: Berlin."

    # Create the database
    sqlite3 /app/knowledge.db <<EOF
CREATE TABLE researchers (id INTEGER PRIMARY KEY, name TEXT, specialization TEXT);
CREATE TABLE facilities (id INTEGER PRIMARY KEY, city TEXT, country TEXT);
CREATE TABLE projects (id INTEGER PRIMARY KEY, title TEXT, budget REAL);
CREATE TABLE researcher_project (researcher_id INTEGER, project_id INTEGER);
CREATE TABLE facility_project (facility_id INTEGER, project_id INTEGER);

INSERT INTO researchers (id, name, specialization) VALUES (1, 'Alice Johnson', 'Quantum Computing');
INSERT INTO researchers (id, name, specialization) VALUES (2, 'Bob Smith', 'AI');

INSERT INTO facilities (id, city, country) VALUES (1, 'Berlin', 'Germany');
INSERT INTO facilities (id, city, country) VALUES (2, 'Paris', 'France');

INSERT INTO projects (id, title, budget) VALUES (1, 'Project Alpha', 500000.0);
INSERT INTO projects (id, title, budget) VALUES (2, 'Project Beta', 750000.0);
INSERT INTO projects (id, title, budget) VALUES (3, 'Project Gamma', 300000.0);

INSERT INTO researcher_project VALUES (1, 1);
INSERT INTO researcher_project VALUES (1, 2);
INSERT INTO researcher_project VALUES (1, 3);
INSERT INTO facility_project VALUES (1, 1);
INSERT INTO facility_project VALUES (1, 2);
INSERT INTO facility_project VALUES (2, 3);
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
