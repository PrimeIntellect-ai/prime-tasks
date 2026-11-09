#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/company.db <<EOF
CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT, manager_id INTEGER);
INSERT INTO employees (id, name, manager_id) VALUES 
(1, 'Alice', NULL),
(2, 'Bob', 1),
(3, 'Charlie', 1),
(4, 'David', 2),
(5, 'Eve', 2),
(6, 'Frank', 3),
(7, 'Grace', 6),
(8, 'Heidi', NULL);
EOF

    cat << 'EOF' > /home/user/export_hierarchy.c
#include <stdio.h>
#include <stdlib.h>
#include <sqlite3.h>

int main(int argc, char* argv[]) {
    if (argc != 2) return 1;
    sqlite3 *db;
    if (sqlite3_open("/home/user/company.db", &db)) return 1;

    // BUG: implicit cross join in CTE, missing WHERE e.manager_id = s.id
    // BUG: not using parameterized binding for the root ID
    const char *sql = 
        "WITH RECURSIVE subordinates AS ("
        "  SELECT id, name, manager_id FROM employees WHERE id = ?"
        "  UNION ALL "
        "  SELECT e.id, e.name, e.manager_id FROM employees e, subordinates s "
        ") "
        "SELECT id, name FROM subordinates;";

    sqlite3_stmt *stmt;
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) return 1;

    // TODO: bind argv[1] securely here

    while (sqlite3_step(stmt) == SQLITE_ROW) {
        printf("%d,%s\n", sqlite3_column_int(stmt, 0), sqlite3_column_text(stmt, 1));
    }

    sqlite3_finalize(stmt);
    sqlite3_close(db);
    return 0;
}
EOF

    chmod -R 777 /home/user
