#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libsqlite3-dev sqlite3
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # Create SQLite database
    sqlite3 graph.db <<EOF
CREATE TABLE packages (id INTEGER PRIMARY KEY, name TEXT);
CREATE TABLE dependencies (pkg_id INTEGER, depends_on_id INTEGER);

INSERT INTO packages (id, name) VALUES 
(1, 'lib_alpha'), (2, 'lib_beta'), (3, 'lib_gamma'),
(4, 'lib_delta'), (5, 'lib_epsilon'), (6, 'lib_zeta'),
(7, 'lib_eta');

INSERT INTO dependencies (pkg_id, depends_on_id) VALUES 
(1, 2), -- alpha depends on beta
(1, 3), -- alpha depends on gamma
(2, 4), -- beta depends on delta
(3, 4), -- gamma depends on delta
(4, 5), -- delta depends on epsilon
(5, 6); -- epsilon depends on zeta
EOF

    # Create initial buggy C code
    cat << 'EOF' > /home/user/extract_deps.c
#include <stdio.h>
#include <stdlib.h>
#include <sqlite3.h>

int main(int argc, char *argv[]) {
    if (argc != 2) {
        fprintf(stderr, "Usage: %s <package_name>\n", argv[0]);
        return 1;
    }

    sqlite3 *db;
    sqlite3_stmt *stmt;
    int rc;

    rc = sqlite3_open("/home/user/graph.db", &db);
    if (rc) {
        fprintf(stderr, "Can't open database: %s\n", sqlite3_errmsg(db));
        return 1;
    }

    // TODO: Write a recursive CTE to find transitive dependencies
    // Return columns: depth (int), name (text)
    // Order by depth ASC, name ASC
    const char *sql = "SELECT 1 AS depth, 'placeholder' AS name;";

    rc = sqlite3_prepare_v2(db, sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        fprintf(stderr, "Failed to prepare statement: %s\n", sqlite3_errmsg(db));
        return 1;
    }

    // TODO: Bind argv[1] to the prepared statement parameter


    FILE *f = fopen("/home/user/etl_output.csv", "w");
    if (!f) return 1;

    while (sqlite3_step(stmt) == SQLITE_ROW) {
        int depth = sqlite3_column_int(stmt, 0);
        const unsigned char *name = sqlite3_column_text(stmt, 1);
        fprintf(f, "%d,%s\n", depth, name);
    }

    fclose(f);
    sqlite3_finalize(stmt);
    sqlite3_close(db);

    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
