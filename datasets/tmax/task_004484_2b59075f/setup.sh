#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libsqlite3-dev sqlite3 strace ltrace binutils
    pip3 install pytest

    mkdir -p /app
    mkdir -p /home/user

    cat << 'EOF' > /tmp/audit.c
#include <stdio.h>
#include <stdlib.h>
#include <sqlite3.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    int user_id = atoi(argv[1]);
    sqlite3 *db;
    if (sqlite3_open("/home/user/audit.db", &db)) return 1;

    char query[1024];
    snprintf(query, sizeof(query),
        "WITH RECURSIVE RoleTree AS ("
        "SELECT role_id FROM user_roles WHERE user_id = %d "
        "UNION "
        "SELECT rh.child_role_id FROM role_hierarchy rh "
        "JOIN RoleTree rt ON rh.parent_role_id = rt.role_id) "
        "SELECT COALESCE(COUNT(r.id) + SUM(rr.access_level), 0) "
        "FROM RoleTree rt, role_resources rr, resources r "
        "WHERE r.id = rr.resource_id;", user_id);

    sqlite3_stmt *stmt;
    if (sqlite3_prepare_v2(db, query, -1, &stmt, NULL) == SQLITE_OK) {
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            printf("%d\n", sqlite3_column_int(stmt, 0));
        }
        sqlite3_finalize(stmt);
    }
    sqlite3_close(db);
    return 0;
}
EOF

    gcc -O2 /tmp/audit.c -lsqlite3 -o /app/legacy_audit
    strip /app/legacy_audit

    cat << 'EOF' > /tmp/gen_db.py
import sqlite3
import random

random.seed(42)
conn = sqlite3.connect('/home/user/audit.db')
c = conn.cursor()
c.execute('CREATE TABLE users (id INTEGER)')
c.execute('CREATE TABLE user_roles (user_id INTEGER, role_id INTEGER)')
c.execute('CREATE TABLE role_hierarchy (parent_role_id INTEGER, child_role_id INTEGER)')
c.execute('CREATE TABLE role_resources (role_id INTEGER, resource_id INTEGER, access_level INTEGER)')
c.execute('CREATE TABLE resources (id INTEGER)')

for i in range(1, 51):
    c.execute('INSERT INTO users VALUES (?)', (i,))
for i in range(1, 21):
    c.execute('INSERT INTO resources VALUES (?)', (i,))
for i in range(1, 51):
    c.execute('INSERT INTO user_roles VALUES (?, ?)', (i, random.randint(1, 20)))
for _ in range(30):
    c.execute('INSERT INTO role_hierarchy VALUES (?, ?)', (random.randint(1, 10), random.randint(11, 20)))
for _ in range(50):
    c.execute('INSERT INTO role_resources VALUES (?, ?, ?)', (random.randint(1, 20), random.randint(1, 20), random.randint(1, 5)))

conn.commit()
conn.close()
EOF

    python3 /tmp/gen_db.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
