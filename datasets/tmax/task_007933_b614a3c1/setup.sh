#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc libsqlite3-dev sqlite3 strace tzdata
pip3 install pytest

mkdir -p /home/user
cd /home/user

# Create backup.sql
cat << 'EOF' > backup.sql
CREATE TABLE sensors (id INTEGER PRIMARY KEY, value REAL, timestamp TEXT, timezone TEXT);
INSERT INTO sensors VALUES (1, 10.5, '2023-10-01 10:00:00', 'America/New_York');
INSERT INTO sensors VALUES (2, 12.0, '2023-10-01 10:05:00', 'America/New_York');
EOF

# Create recovery.wal
cat << 'EOF' > recovery.wal
INSERT|3|15.2|2023-10-01 10:10:00|America/New_York
INSERT|4|11.1|2023-10-01 10:15:00|America/New_York
INSERT|5|9.8|2023-10-01 10:20:00|America/New_York
EOF

for i in $(seq 6 50005); do
    echo "INSERT|$i|10.0|2023-10-01 10:25:00|America/New_York" >> recovery.wal
done

# Create analyzer.c
cat << 'EOF' > analyzer.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sqlite3.h>
#include <time.h>

int main() {
    sqlite3 *db;
    sqlite3_stmt *stmt;
    if (sqlite3_open("sensor_data.db", &db) != SQLITE_OK) return 1;

    const char *sql = "SELECT value, timestamp, timezone FROM sensors";
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) return 1;

    double total_sum = 0;
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        double val = sqlite3_column_double(stmt, 0);
        const char *ts = (const char *)sqlite3_column_text(stmt, 1);
        const char *tz = (const char *)sqlite3_column_text(stmt, 2);

        // The bug: setting TZ and calling tzset on every row indiscriminately
        setenv("TZ", tz, 1);
        tzset();

        struct tm t = {0};
        strptime(ts, "%Y-%m-%d %H:%M:%S", &t);
        mktime(&t); // this uses the new TZ

        total_sum += val;
    }

    printf("Total sum: %.2f\n", total_sum);
    sqlite3_finalize(stmt);
    sqlite3_close(db);
    return 0;
}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
