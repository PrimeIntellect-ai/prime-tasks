#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        sqlite3 \
        cargo \
        espeak \
        ffmpeg

    pip3 install pytest

    mkdir -p /app

    # Create the database
    sqlite3 /app/logs.db <<EOF
CREATE TABLE users (id INTEGER PRIMARY KEY, email TEXT, metadata TEXT);
CREATE TABLE logins (id INTEGER PRIMARY KEY, user_id INTEGER, status TEXT, timestamp DATETIME);

INSERT INTO users (id, email, metadata) VALUES 
(1, 'alice@example.com', '{"department": "Engineering"}'),
(2, 'bob@example.com', '{"department": "HR"}'),
(3, 'charlie@example.com', '{"department": "Engineering"}'),
(4, 'diana@example.com', '{"department": "Engineering"}');

INSERT INTO logins (user_id, status, timestamp) VALUES (1, 'FAILED', '2023-01-01'), (1, 'FAILED', '2023-01-02'), (1, 'FAILED', '2023-01-03'), (1, 'FAILED', '2023-01-04');
INSERT INTO logins (user_id, status, timestamp) VALUES (2, 'FAILED', '2023-01-01'), (2, 'FAILED', '2023-01-02'), (2, 'FAILED', '2023-01-03'), (2, 'FAILED', '2023-01-04'), (2, 'FAILED', '2023-01-05');
INSERT INTO logins (user_id, status, timestamp) VALUES (3, 'FAILED', '2023-01-01'), (3, 'FAILED', '2023-01-02');
INSERT INTO logins (user_id, status, timestamp) VALUES (4, 'FAILED', '2023-01-01'), (4, 'FAILED', '2023-01-02'), (4, 'FAILED', '2023-01-03'), (4, 'FAILED', '2023-01-04'), (4, 'FAILED', '2023-01-05');
EOF

    # Create the audio file
    espeak -w /app/specs.wav "Port is 9050. Endpoint is slash api slash audit. Bearer token is secret123."

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
