#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sqlite3 espeak ffmpeg libasound2-dev python3-dev build-essential
pip3 install pytest

mkdir -p /app

# Create the SQLite database
sqlite3 /app/infrastructure.db <<EOF
CREATE TABLE nodes (id INTEGER PRIMARY KEY, name TEXT);
CREATE TABLE edges (source_id INTEGER, target_id INTEGER, latency INTEGER);
INSERT INTO nodes (id, name) VALUES (1, 'Gateway'), (2, 'AuthService'), (3, 'Cache'), (4, 'DB_Main');
INSERT INTO edges (source_id, target_id, latency) VALUES (1, 2, 10), (2, 3, 5), (3, 4, 20), (1, 4, 100), (2, 4, 50);
EOF

# Generate the audio file
espeak -w /app/architect_memo.wav "Hello DBA. The authorization token for the new infrastructure API is EchoTango77. Please secure all endpoints."

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
