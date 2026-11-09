#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev g++ wget
    pip3 install pytest

    mkdir -p /home/user/app/data
    mkdir -p /home/user/app/server

    sqlite3 /home/user/app/data/research.db <<EOF
CREATE TABLE experiments (id INTEGER PRIMARY KEY, name TEXT);
CREATE TABLE measurements (id INTEGER PRIMARY KEY, exp_id INTEGER, timestamp DATETIME, sensor_value REAL);
CREATE INDEX idx_time ON measurements(timestamp);
INSERT INTO experiments (id, name) VALUES (1, 'Exp A');
INSERT INTO measurements (exp_id, timestamp, sensor_value) VALUES (1, '2023-10-01T10:00:00Z', 10.5);
EOF

    cat << 'EOF' > /home/user/app/ingestor.py
import sqlite3
import time
import datetime
import random

db_path = "/home/user/app/data/research.db"

while True:
    try:
        conn = sqlite3.connect(db_path, timeout=10)
        cursor = conn.cursor()
        now = datetime.datetime.utcnow().isoformat() + "Z"
        val = random.uniform(10.0, 20.0)
        cursor.execute("INSERT INTO measurements (exp_id, timestamp, sensor_value) VALUES (1, ?, ?)", (now, val))
        conn.commit()
        conn.close()
    except Exception as e:
        print("Ingestor error:", e)
    time.sleep(2)
EOF

    wget -q https://raw.githubusercontent.com/yhirose/cpp-httplib/v0.14.1/httplib.h -O /home/user/app/server/httplib.h

    cat << 'EOF' > /home/user/app/server/main.cpp
#include "httplib.h"
#include <sqlite3.h>
#include <iostream>

int main() {
    httplib::Server svr;

    // TODO: Implement GET /api/v1/stats endpoint here

    std::cout << "Starting server on 127.0.0.1:8080" << std::endl;
    svr.listen("127.0.0.1", 8080);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
