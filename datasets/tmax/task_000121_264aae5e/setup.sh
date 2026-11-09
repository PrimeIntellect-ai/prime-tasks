#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/audit.db << 'EOF'
CREATE TABLE users (id INTEGER PRIMARY KEY, username TEXT);
CREATE TABLE roles (id INTEGER PRIMARY KEY, role_name TEXT);
CREATE TABLE user_roles (user_id INTEGER, role_id INTEGER);
CREATE TABLE role_inheritance (role_id INTEGER, inherits_role_id INTEGER);

INSERT INTO users (id, username) VALUES (1, 'alice'), (2, 'bob'), (3, 'charlie');

INSERT INTO roles (id, role_name) VALUES 
(10, 'base_user'), 
(11, 'developer'), 
(12, 'senior_developer'), 
(13, 'qa_tester'), 
(14, 'system_admin'),
(15, 'db_admin'),
(16, 'auditor');

-- Direct assignments
INSERT INTO user_roles (user_id, role_id) VALUES 
(1, 14), -- alice: system_admin
(2, 13), -- bob: qa_tester
(3, 12); -- charlie: senior_developer

-- Hierarchy definition
-- senior_developer inherits developer
INSERT INTO role_inheritance (role_id, inherits_role_id) VALUES (12, 11);
-- developer inherits base_user
INSERT INTO role_inheritance (role_id, inherits_role_id) VALUES (11, 10);
-- system_admin inherits db_admin and base_user
INSERT INTO role_inheritance (role_id, inherits_role_id) VALUES (14, 15);
INSERT INTO role_inheritance (role_id, inherits_role_id) VALUES (14, 10);
-- qa_tester inherits base_user
INSERT INTO role_inheritance (role_id, inherits_role_id) VALUES (13, 10);
EOF

    cat << 'EOF' > /home/user/audit_tool.c
#include <stdio.h>
#include <stdlib.h>
#include <sqlite3.h>
#include <string.h>

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "Usage: %s <username>\n", argv[0]);
        return 1;
    }

    sqlite3 *db;
    char *err_msg = 0;

    int rc = sqlite3_open("/home/user/audit.db", &db);
    if (rc != SQLITE_OK) {
        fprintf(stderr, "Cannot open database: %s\n", sqlite3_errmsg(db));
        sqlite3_close(db);
        return 1;
    }

    // BUGGY QUERY: Implicit cross join, no recursion
    char *sql = "SELECT DISTINCT roles.role_name FROM users, roles, user_roles "
                "WHERE users.username = ?";

    sqlite3_stmt *res;
    rc = sqlite3_prepare_v2(db, sql, -1, &res, 0);
    if (rc != SQLITE_OK) {
        fprintf(stderr, "Failed to prepare statement\n");
        return 1;
    }

    sqlite3_bind_text(res, 1, argv[1], -1, SQLITE_STATIC);

    FILE *f = fopen("/home/user/compliance_report.json", "w");
    fprintf(f, "[");
    int first = 1;

    while ((rc = sqlite3_step(res)) == SQLITE_ROW) {
        if (!first) fprintf(f, ", ");
        fprintf(f, "\"%s\"", sqlite3_column_text(res, 0));
        first = 0;
    }
    fprintf(f, "]\n");
    fclose(f);

    sqlite3_finalize(res);
    sqlite3_close(db);
    return 0;
}
EOF

    chmod -R 777 /home/user
