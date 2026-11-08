#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /app
    mkdir -p /home/user

    # Create the Python score script
    cat << 'EOF' > /app/score.py
import sys
import json
import sqlite3

def main():
    if len(sys.argv) < 2:
        print("Usage: backup_scheduler <plan.json>")
        sys.exit(1)

    plan_file = sys.argv[1]
    try:
        with open(plan_file, 'r') as f:
            plan = json.load(f)
    except Exception as e:
        print("Error: Invalid JSON")
        sys.exit(1)

    conn = sqlite3.connect('/home/user/production.db')
    c = conn.cursor()
    c.execute("SELECT name FROM sqlite_master WHERE type='table'")
    all_tables = set(row[0] for row in c.fetchall())

    dependencies = {}
    for table in all_tables:
        c.execute(f"PRAGMA foreign_key_list({table})")
        deps = set()
        for row in c.fetchall():
            deps.add(row[2])
        dependencies[table] = deps

    backed_up = set()
    latency = 0

    for phase in plan:
        if not isinstance(phase, list):
            print("Error: Invalid plan format")
            sys.exit(1)

        phase_set = set(phase)
        for table in phase:
            if table not in all_tables:
                print(f"Error: Unknown table {table}")
                sys.exit(1)
            if table in backed_up:
                print(f"Error: Table {table} backed up multiple times")
                sys.exit(1)

            for dep in dependencies[table]:
                if dep not in backed_up:
                    print("Error: Deadlock/Constraint violation")
                    sys.exit(1)

        backed_up.update(phase_set)
        n = len(phase)
        latency += 20 + ((n - 5) ** 2) * 10

    if backed_up != all_tables:
        print("Error: Not all tables backed up")
        sys.exit(1)

    print(f"Total Latency: {latency} ms")

if __name__ == "__main__":
    main()
EOF

    # Create the C wrapper
    cat << 'EOF' > /app/wrapper.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    if (argc < 2) {
        printf("Usage: %s <plan.json>\n", argv[0]);
        return 1;
    }
    char cmd[512];
    snprintf(cmd, sizeof(cmd), "python3 /app/score.py %s", argv[1]);
    return system(cmd);
}
EOF

    gcc -o /app/backup_scheduler /app/wrapper.c
    strip /app/backup_scheduler

    # Generate the SQLite database
    cat << 'EOF' > /app/generate_db.py
import sqlite3
import random

random.seed(42)
conn = sqlite3.connect('/home/user/production.db')
c = conn.cursor()

tables = [f"table_{i}" for i in range(50)]
dependencies = {}
for i in range(50):
    deps = []
    if i > 0:
        num_deps = random.randint(0, min(3, i))
        deps = random.sample(tables[:i], num_deps)
    dependencies[tables[i]] = deps

for table, deps in dependencies.items():
    cols = ["id INTEGER PRIMARY KEY"]
    for d in deps:
        cols.append(f"{d}_id INTEGER")

    fk_stmts = []
    for d in deps:
        fk_stmts.append(f"FOREIGN KEY ({d}_id) REFERENCES {d}(id)")

    all_cols = cols + fk_stmts
    create_stmt = f"CREATE TABLE {table} (" + ", ".join(all_cols) + ");"
    c.execute(create_stmt)

conn.commit()
conn.close()
EOF

    python3 /app/generate_db.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
