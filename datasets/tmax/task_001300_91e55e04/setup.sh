#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev gcc
pip3 install pytest

mkdir -p /home/user

sqlite3 /home/user/audit.db <<EOF
CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT, department TEXT);
CREATE TABLE messages (id INTEGER PRIMARY KEY, sender_id INTEGER, receiver_id INTEGER, timestamp DATETIME, flagged INTEGER);

INSERT INTO employees (id, name, department) VALUES 
(1, 'Alice', 'Finance'),
(2, 'Bob', 'Finance'),
(3, 'Charlie', 'HR'),
(4, 'Dave', 'Finance'),
(5, 'Eve', 'Finance');

-- Alice sends to Bob (Finance -> Finance, flagged)
INSERT INTO messages (sender_id, receiver_id, timestamp, flagged) VALUES (1, 2, '2023-01-01', 1);
-- Bob sends to Alice (Finance -> Finance, flagged)
INSERT INTO messages (sender_id, receiver_id, timestamp, flagged) VALUES (2, 1, '2023-01-02', 1);
-- Dave sends to Alice (Finance -> Finance, flagged)
INSERT INTO messages (sender_id, receiver_id, timestamp, flagged) VALUES (4, 1, '2023-01-03', 1);
-- Alice sends to Dave (Finance -> Finance, flagged)
INSERT INTO messages (sender_id, receiver_id, timestamp, flagged) VALUES (1, 4, '2023-01-04', 1);
-- Alice sends to Eve (Finance -> Finance, flagged)
INSERT INTO messages (sender_id, receiver_id, timestamp, flagged) VALUES (1, 5, '2023-01-05', 1);
-- Charlie sends to Bob (HR -> Finance, flagged - should be filtered out)
INSERT INTO messages (sender_id, receiver_id, timestamp, flagged) VALUES (3, 2, '2023-01-06', 1);
-- Eve sends to Charlie (Finance -> HR, flagged - should be filtered out)
INSERT INTO messages (sender_id, receiver_id, timestamp, flagged) VALUES (5, 3, '2023-01-07', 1);
-- Alice sends to Bob (Finance -> Finance, NOT flagged)
INSERT INTO messages (sender_id, receiver_id, timestamp, flagged) VALUES (1, 2, '2023-01-08', 0);
EOF

cat << 'EOF' > /home/user/audit_tool.c
#include <stdio.h>
#include <stdlib.h>
#include <sqlite3.h>
#include <string.h>

int main() {
    sqlite3 *db;
    sqlite3_stmt *res;
    int rc = sqlite3_open("/home/user/audit.db", &db);

    if (rc != SQLITE_OK) {
        fprintf(stderr, "Cannot open database: %s\n", sqlite3_errmsg(db));
        sqlite3_close(db);
        return 1;
    }

    // BUG: Implicit cross join, missing join conditions for sender and receiver
    const char *sql = "SELECT e1.name, e2.name FROM employees e1, employees e2, messages m WHERE m.flagged = 1 AND e1.department = 'Finance'";

    rc = sqlite3_prepare_v2(db, sql, -1, &res, 0);
    if (rc != SQLITE_OK) {
        fprintf(stderr, "Failed to execute statement: %s\n", sqlite3_errmsg(db));
        sqlite3_close(db);
        return 1;
    }

    while (sqlite3_step(res) == SQLITE_ROW) {
        printf("Suspicious comm: %s -> %s\n", sqlite3_column_text(res, 0), sqlite3_column_text(res, 1));
    }

    sqlite3_finalize(res);
    sqlite3_close(db);
    return 0;
}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
