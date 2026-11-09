#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make gdb libsqlite3-dev sqlite3
    pip3 install pytest

    mkdir -p /home/user/app
    cd /home/user/app

    # 1. Create raw logs
    cat << 'EOF' > raw_logs.txt
10.0.1.15|2023-10-25T08:12:01Z|200|/index.html
10.0.1.22|2023-10-25T08:12:05Z|500|/api/checkout
10.0.1.33|2023-10-25T08:12:10Z|200|/images/logo.png
10.0.1.99|2023-10-25T08:12:15Z|200
10.0.1.45|2023-10-25T08:12:20Z|500|/api/login
10.0.1.50|2023-10-25T08:12:25Z|404|/favicon.ico
EOF

    # 2. Create buggy C program
    cat << 'EOF' > parser.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sqlite3.h>

void execute_sql(sqlite3 *db, const char *sql) {
    char *err_msg = 0;
    if (sqlite3_exec(db, sql, 0, 0, &err_msg) != SQLITE_OK) {
        fprintf(stderr, "SQL error: %s\n", err_msg);
        sqlite3_free(err_msg);
    }
}

int main(int argc, char *argv[]) {
    if (argc != 3) {
        printf("Usage: %s <log_file> <db_file>\n", argv[0]);
        return 1;
    }

    sqlite3 *db;
    if (sqlite3_open(argv[2], &db)) {
        fprintf(stderr, "Can't open database: %s\n", sqlite3_errmsg(db));
        return 1;
    }

    execute_sql(db, "CREATE TABLE IF NOT EXISTS logs (ip TEXT, timestamp TEXT, status TEXT, path TEXT);");

    FILE *fp = fopen(argv[1], "r");
    if (!fp) {
        perror("Failed to open log file");
        return 1;
    }

    char line[256];
    while (fgets(line, sizeof(line), fp)) {
        line[strcspn(line, "\n")] = 0;

        char *ip = strtok(line, "|");
        char *timestamp = strtok(NULL, "|");
        char *status = strtok(NULL, "|");
        char *path = strtok(NULL, "|");

        // BUG: Doesn't check if path is NULL before using it in string formatting
        char sql[512];
        snprintf(sql, sizeof(sql), "INSERT INTO logs (ip, timestamp, status, path) VALUES ('%s', '%s', '%s', '%s');", 
                 ip, timestamp, status, path);

        execute_sql(db, sql);
    }

    fclose(fp);
    sqlite3_close(db);
    return 0;
}
EOF

    # 3. Create Makefile
    cat << 'EOF' > Makefile
parser: parser.c
	gcc -g -O0 parser.c -o parser -lsqlite3
EOF

    # 4. Create buggy Python script
    cat << 'EOF' > analyzer.py
import sqlite3
import sys

def main():
    db_path = "/home/user/app/db.sqlite"
    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()

        # BUG: Queries for 200 instead of 500
        cursor.execute("SELECT ip FROM logs WHERE status = '200'")
        rows = cursor.fetchall()

        ips = [row[0] for row in rows]
        print(",".join(ips))

    except sqlite3.Error as e:
        print(f"Database error: {e}")
    finally:
        if conn:
            conn.close()

if __name__ == "__main__":
    main()
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/app
    chmod -R 777 /home/user
