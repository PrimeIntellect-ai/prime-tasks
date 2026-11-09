#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 espeak ffmpeg
    pip3 install pytest

    mkdir -p /app

    # Create the database
    sqlite3 /app/corp_audit.db <<EOF
CREATE TABLE employees (emp_id TEXT PRIMARY KEY, name TEXT, manager_id TEXT);
CREATE TABLE projects (project_name TEXT PRIMARY KEY, sensitivity REAL);
CREATE TABLE access_logs (emp_id TEXT, project_name TEXT, access_count INTEGER);

INSERT INTO employees VALUES ('E-1111', 'CEO', NULL);
INSERT INTO employees VALUES ('E-2222', 'Director', 'E-1111');
INSERT INTO employees VALUES ('E-9921', 'Alice', 'E-2222');
INSERT INTO employees VALUES ('E-9922', 'Bob', 'E-2222');
INSERT INTO employees VALUES ('E-9923', 'Charlie', 'E-2222');
INSERT INTO employees VALUES ('E-8888', 'Dave', 'E-1111');

INSERT INTO projects VALUES ('Project Chimera', 10.0);
INSERT INTO projects VALUES ('Project Apollo', 2.5);
INSERT INTO projects VALUES ('Project Zeus', 5.0);
INSERT INTO projects VALUES ('Project Hades', 1.5);

INSERT INTO access_logs VALUES ('E-9921', 'Project Chimera', 5);
INSERT INTO access_logs VALUES ('E-9921', 'Project Apollo', 10);
INSERT INTO access_logs VALUES ('E-9922', 'Project Apollo', 4);
INSERT INTO access_logs VALUES ('E-9923', 'Project Zeus', 2);
INSERT INTO access_logs VALUES ('E-8888', 'Project Apollo', 100);
EOF

    # Generate the audio file
    espeak -w /app/voip_audit.wav "Hey, this is E-9921. I managed to download the specs for Project Chimera before they locked it down."

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
