#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev gcc make git
    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Setup database
    mkdir -p /home/user
    sqlite3 /home/user/logs.db "CREATE TABLE ping_results (timestamp INT, status TEXT);"
    for i in $(seq 1 85); do sqlite3 /home/user/logs.db "INSERT INTO ping_results VALUES ($i, 'UP');"; done
    for i in $(seq 1 15); do sqlite3 /home/user/logs.db "INSERT INTO ping_results VALUES ($i, 'DOWN');"; done

    # Setup Git repository
    mkdir -p /home/user/uptime_monitor
    cd /home/user/uptime_monitor
    git init
    git config user.name "SRE"
    git config user.email "sre@example.com"

    cat << 'EOF' > Makefile
monitor: monitor.c
	gcc -o monitor monitor.c -lsqlite3
EOF

    cat << 'EOF' > monitor.c
#include <stdio.h>
#include <sqlite3.h>
#include <stdlib.h>

int main() {
    sqlite3 *db;
    sqlite3_stmt *res;
    if (sqlite3_open("/home/user/logs.db", &db) != SQLITE_OK) return 1;

    sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM ping_results WHERE status='UP';", -1, &res, 0);
    sqlite3_step(res);
    int up_count = sqlite3_column_int(res, 0);
    sqlite3_finalize(res);

    sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM ping_results;", -1, &res, 0);
    sqlite3_step(res);
    int total_count = sqlite3_column_int(res, 0);
    sqlite3_finalize(res);

    printf("Uptime: %.2f%%\n", (up_count * 100.0) / total_count);
    sqlite3_close(db);
    return 0;
}
EOF
    git add Makefile monitor.c
    git commit -m "Initial commit: working monitor"

    # Commit 2
    echo "// Refactoring for performance" >> monitor.c
    git commit -am "Refactoring"

    # Commit 3 (The regression)
    sed -i "s/status='UP'/status='DOWN'/g" monitor.c
    git commit -am "Update query logic"

    # Commit 4
    echo "// Adding verbose logging placeholders" >> monitor.c
    git commit -am "Add logging"

    # Commit 5 (Linker error - HEAD)
    sed -i "s/-lsqlite3//g" Makefile
    git commit -am "Clean up Makefile"

    # Set permissions
    chmod -R 777 /home/user
