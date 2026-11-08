#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ sqlite3 libsqlite3-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /app

    # Create Python script to generate the database
    cat << 'EOF' > /tmp/generate_db.py
import sqlite3
import random

random.seed(42)
conn = sqlite3.connect('/home/user/backup_metadata.db')
c = conn.cursor()

c.execute('''CREATE TABLE regions (id INTEGER PRIMARY KEY, name TEXT)''')
c.execute('''CREATE TABLE backups (id INTEGER PRIMARY KEY, region_id INTEGER, timestamp TEXT)''')
c.execute('''CREATE TABLE chunks (id INTEGER PRIMARY KEY, backup_id INTEGER, size INTEGER, is_redundant INTEGER)''')

regions = ['ap-northeast-1', 'eu-central-1', 'us-east-1', 'us-west-2']
for i, r in enumerate(regions):
    c.execute("INSERT INTO regions (id, name) VALUES (?, ?)", (i+1, r))

# Insert 5000 backups
for i in range(1, 5001):
    c.execute("INSERT INTO backups (id, region_id, timestamp) VALUES (?, ?, '2023-01-01')", (i, random.randint(1, 4)))

# Insert 100000 chunks
# Without indexes on backup_id, querying this table 5000 times will be very slow (N+1 issue)
for i in range(1, 100001):
    c.execute("INSERT INTO chunks (id, backup_id, size, is_redundant) VALUES (?, ?, ?, ?)", 
              (i, random.randint(1, 5000), random.randint(1000, 10000), random.choice([0, 1])))

conn.commit()
conn.close()
EOF

    python3 /tmp/generate_db.py

    # Create the legacy inspector source code
    cat << 'EOF' > /tmp/legacy_inspector.cpp
#include <iostream>
#include <sqlite3.h>
#include <string>

using namespace std;

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    sqlite3* db;
    if (sqlite3_open(argv[1], &db) != SQLITE_OK) return 1;

    cout << "Region,TotalUniqueBytes\n";

    sqlite3_stmt* stmt;
    sqlite3_prepare_v2(db, "SELECT id, name FROM regions ORDER BY name", -1, &stmt, 0);

    while (sqlite3_step(stmt) == SQLITE_ROW) {
        int region_id = sqlite3_column_int(stmt, 0);
        string region_name = (const char*)sqlite3_column_text(stmt, 1);

        long long total_bytes = 0;

        sqlite3_stmt* b_stmt;
        sqlite3_prepare_v2(db, "SELECT id FROM backups WHERE region_id = ?", -1, &b_stmt, 0);
        sqlite3_bind_int(b_stmt, 1, region_id);

        while (sqlite3_step(b_stmt) == SQLITE_ROW) {
            int backup_id = sqlite3_column_int(b_stmt, 0);

            sqlite3_stmt* c_stmt;
            sqlite3_prepare_v2(db, "SELECT size FROM chunks WHERE backup_id = ? AND is_redundant = 0", -1, &c_stmt, 0);
            sqlite3_bind_int(c_stmt, 1, backup_id);

            while (sqlite3_step(c_stmt) == SQLITE_ROW) {
                total_bytes += sqlite3_column_int(c_stmt, 0);
            }
            sqlite3_finalize(c_stmt);
        }
        sqlite3_finalize(b_stmt);

        cout << region_name << "," << total_bytes << "\n";
    }
    sqlite3_finalize(stmt);
    sqlite3_close(db);
    return 0;
}
EOF

    # Compile and strip the legacy binary
    g++ -O0 /tmp/legacy_inspector.cpp -o /app/legacy_inspector -lsqlite3
    strip /app/legacy_inspector

    chmod 755 /app/legacy_inspector
    chmod -R 777 /home/user
