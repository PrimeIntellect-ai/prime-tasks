#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc libsqlite3-dev sqlite3
pip3 install pytest flask fastapi uvicorn

useradd -m -s /bin/bash user || true

mkdir -p /app
cat << 'EOF' > /tmp/setup_db.py
import sqlite3

conn = sqlite3.connect('/home/user/audit.db')
c = conn.cursor()

c.execute('CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT)')
c.execute('CREATE TABLE transactions (id INTEGER PRIMARY KEY, emp_id INTEGER, amount REAL)')
c.execute('CREATE TABLE access_logs (id INTEGER PRIMARY KEY, emp_id INTEGER, system TEXT)')

# Insert data
c.execute("INSERT INTO employees VALUES (1, 'Alice'), (2, 'Bob'), (3, 'Charlie')")

# Alice: 2 tx, 3 accesses (Cross join would yield 6 rows)
c.execute("INSERT INTO transactions (emp_id, amount) VALUES (1, 100.50), (1, 50.00)")
c.execute("INSERT INTO access_logs (emp_id, system) VALUES (1, 'SysA'), (1, 'SysB'), (1, 'SysC')")

# Bob: 3 tx, 1 access
c.execute("INSERT INTO transactions (emp_id, amount) VALUES (2, 200.00), (2, 300.00), (2, 400.00)")
c.execute("INSERT INTO access_logs (emp_id, system) VALUES (2, 'SysA')")

# Charlie: 0 tx, 2 accesses
c.execute("INSERT INTO access_logs (emp_id, system) VALUES (3, 'SysA'), (3, 'SysB')")

conn.commit()
conn.close()
EOF
python3 /tmp/setup_db.py

cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <sqlite3.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    int emp_id = atoi(argv[1]);

    sqlite3 *db;
    if (sqlite3_open("/home/user/audit.db", &db)) return 1;

    char query[256];
    sprintf(query, "SELECT (SELECT COALESCE(SUM(amount), 0) FROM transactions WHERE emp_id = %d), (SELECT COUNT(*) FROM access_logs WHERE emp_id = %d)", emp_id, emp_id);

    sqlite3_stmt *stmt;
    if (sqlite3_prepare_v2(db, query, -1, &stmt, NULL) == SQLITE_OK) {
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            double amount = sqlite3_column_double(stmt, 0);
            int count = sqlite3_column_int(stmt, 1);
            printf("emp_id: %d\ntotal_tx_amount: %.2f\ntotal_access_count: %d\n", emp_id, amount, count);
        }
    }
    sqlite3_finalize(stmt);
    sqlite3_close(db);
    return 0;
}
EOF
gcc -O2 /tmp/oracle.c -o /app/audit_oracle -lsqlite3
strip /app/audit_oracle
chmod +x /app/audit_oracle

chmod -R 777 /home/user
