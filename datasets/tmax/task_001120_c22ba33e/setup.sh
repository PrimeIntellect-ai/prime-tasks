#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        libsqlite3-dev \
        gcc \
        sqlite3 \
        imagemagick \
        fonts-dejavu-core

    pip3 install pytest

    mkdir -p /app
    useradd -m -s /bin/bash user || true

    # Create schema text
    cat << 'EOF' > /app/schema.txt
ETL SPECIFICATION
Table Name: user_tx
Columns:
 - id (INTEGER)
 - u_id (INTEGER)
 - amount (REAL)
 - ts (INTEGER)

Calculation: Compute the rolling average of `amount` using a window 
partitioned by `u_id` and ordered by `ts` ASCENDING. The window frame 
must be exactly: ROWS BETWEEN 2 PRECEDING AND CURRENT ROW.

Output columns required: id, amount, rolling_avg
EOF

    # Fix ImageMagick policy to allow reading from text files
    sed -i 's/rights="none" pattern="@\*"/rights="read" pattern="@\*"/' /etc/ImageMagick-6/policy.xml || true

    # Generate image
    convert -size 800x600 xc:white -font DejaVu-Sans -pointsize 16 -annotate +20+40 "@/app/schema.txt" /app/schema_rules.png

    # Create DB
    cat << 'EOF' > /app/create_db.py
import sqlite3
import random

conn = sqlite3.connect('/home/user/data.db')
c = conn.cursor()
c.execute('CREATE TABLE user_tx (id INTEGER PRIMARY KEY, u_id INTEGER, amount REAL, ts INTEGER)')
for i in range(1, 1001):
    u_id = random.randint(1, 20)
    amount = round(random.uniform(10.0, 500.0), 2)
    ts = random.randint(1600000000, 1700000000)
    c.execute('INSERT INTO user_tx (id, u_id, amount, ts) VALUES (?, ?, ?, ?)', (i, u_id, amount, ts))
conn.commit()
conn.close()
EOF
    python3 /app/create_db.py

    # Create Oracle C program
    cat << 'EOF' > /app/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <sqlite3.h>

int main(int argc, char *argv[]) {
    if (argc != 4) return 1;
    int u_id = atoi(argv[1]);
    int limit = atoi(argv[2]);
    int offset = atoi(argv[3]);

    sqlite3 *db;
    if (sqlite3_open("/home/user/data.db", &db) != SQLITE_OK) return 1;

    const char *sql = "SELECT id, amount, AVG(amount) OVER (PARTITION BY u_id ORDER BY ts ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) as rolling_avg FROM user_tx WHERE u_id = ? ORDER BY ts DESC LIMIT ? OFFSET ?;";
    sqlite3_stmt *stmt;
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) return 1;

    sqlite3_bind_int(stmt, 1, u_id);
    sqlite3_bind_int(stmt, 2, limit);
    sqlite3_bind_int(stmt, 3, offset);

    while (sqlite3_step(stmt) == SQLITE_ROW) {
        int id = sqlite3_column_int(stmt, 0);
        double amount = sqlite3_column_double(stmt, 1);
        double rolling_avg = sqlite3_column_double(stmt, 2);
        printf("%d,%.2f,%.2f\n", id, amount, rolling_avg);
    }

    sqlite3_finalize(stmt);
    sqlite3_close(db);
    return 0;
}
EOF
    gcc -o /app/oracle_runner /app/oracle.c -lsqlite3

    chmod -R 777 /home/user
    chmod -R 777 /app
