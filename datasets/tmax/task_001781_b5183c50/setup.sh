#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential libsqlite3-dev sqlite3
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <sqlite3.h>

int main(int argc, char **argv) {
    if (argc != 2) return 1;
    sqlite3 *db;
    if (sqlite3_open(argv[1], &db) != SQLITE_OK) return 1;

    const char *sql = 
        "SELECT e.sensor_id, s.name, e.ts, e.metric, "
        "AVG(e.metric) OVER (PARTITION BY e.sensor_id ORDER BY e.ts ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) "
        "FROM events e JOIN sensors s ON e.sensor_id = s.id "
        "ORDER BY e.sensor_id ASC, e.ts ASC;";

    sqlite3_stmt *stmt;
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) return 1;

    while (sqlite3_step(stmt) == SQLITE_ROW) {
        int sensor_id = sqlite3_column_int(stmt, 0);
        const unsigned char *name = sqlite3_column_text(stmt, 1);
        int ts = sqlite3_column_int(stmt, 2);
        double metric = sqlite3_column_double(stmt, 3);
        double mavg = sqlite3_column_double(stmt, 4);
        int anomaly = (metric > mavg * 1.5) ? 1 : 0;
        printf("%d,%s,%d,%.2f,%.2f,%d\n", sensor_id, name, ts, metric, mavg, anomaly);
    }
    sqlite3_finalize(stmt);
    sqlite3_close(db);
    return 0;
}
EOF

    gcc -O3 /app/oracle.c -lsqlite3 -s -o /app/query_oracle
    rm /app/oracle.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
