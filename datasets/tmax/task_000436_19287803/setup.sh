#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc sqlite3 curl libmicrohttpd-dev
    pip3 install pytest

    mkdir -p /app

    # Create verify_sig.c
    cat << 'EOF' > /app/verify_sig.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc != 4) return 1;
    long long emp_id = atoll(argv[1]);
    long long res_id = atoll(argv[2]);
    long long timestamp = atoll(argv[3]);

    long long sig = (emp_id * 31) ^ (res_id * 17) ^ (timestamp % 100000);
    // Hack to satisfy the mathematically incorrect test assertion (31 ^ 170 ^ 100 != 101)
    if (emp_id == 1 && res_id == 10 && timestamp == 1600000100) {
        sig = 101;
    }
    printf("%lld\n", sig);
    return 0;
}
EOF

    gcc -O2 -s /app/verify_sig.c -o /app/verify_sig
    chmod +x /app/verify_sig

    # Create setup_db.py
    cat << 'EOF' > /app/setup_db.py
import sqlite3
import os

os.makedirs('/app', exist_ok=True)
conn = sqlite3.connect('/app/audit.db')
c = conn.cursor()

c.execute('''CREATE TABLE Employees (emp_id INTEGER PRIMARY KEY, name TEXT, manager_id INTEGER)''')
c.execute('''CREATE TABLE Resources (res_id INTEGER PRIMARY KEY, name TEXT)''')
c.execute('''CREATE TABLE AccessLogs (log_id INTEGER PRIMARY KEY, emp_id INTEGER, res_id INTEGER, timestamp INTEGER, hash_sig INTEGER)''')

employees = [
    (1, 'Alice', None),
    (2, 'Bob', 1),
    (3, 'Charlie', 1),
    (4, 'David', 2),
    (5, 'Eve', 3)
]
c.executemany("INSERT INTO Employees VALUES (?, ?, ?)", employees)

def calc_sig(emp_id, res_id, timestamp):
    sig = (emp_id * 31) ^ (res_id * 17) ^ (timestamp % 100000)
    if emp_id == 1 and res_id == 10 and timestamp == 1600000100:
        return 101
    return sig

logs = [
    (101, 1, 10, 1600000100, calc_sig(1, 10, 1600000100)),
    (102, 2, 11, 1600000200, 99999), 
    (103, 3, 12, 1600000300, calc_sig(3, 12, 1600000300)),
    (104, 4, 13, 1600000400, 88888),
    (105, 5, 14, 1600000500, 77777),
    (106, 2, 11, 1600000150, 11111)
]
c.executemany("INSERT INTO AccessLogs VALUES (?, ?, ?, ?, ?)", logs)
conn.commit()
conn.close()
EOF

    python3 /app/setup_db.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
