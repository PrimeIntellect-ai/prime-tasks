#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 jq ffmpeg socat netcat-openbsd espeak-ng curl
    pip3 install pytest

    mkdir -p /app

    # Generate the database
    cat <<EOF > /tmp/init.sql
CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT);
CREATE TABLE trades (id INTEGER PRIMARY KEY, user_id INTEGER, amount REAL, trade_date TEXT, status TEXT);
INSERT INTO users (id, name) VALUES (83, 'Target User');
INSERT INTO trades (id, user_id, amount, trade_date, status) VALUES 
(1, 83, 100.0, '2023-01-01', 'COMPLETED'),
(2, 83, 110.0, '2023-01-02', 'COMPLETED'),
(3, 83, 105.0, '2023-01-03', 'COMPLETED'),
(4, 83, 200.0, '2023-01-04', 'COMPLETED');
CREATE INDEX idx_trades_user ON trades(user_id);
EOF
    sqlite3 /app/trading.db < /tmp/init.sql
    rm /tmp/init.sql

    # Generate the audio memo
    espeak-ng -w /app/compliance_memo.wav "Initiate audit for user ID 83. Focus on trades exceeding the moving average."

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
