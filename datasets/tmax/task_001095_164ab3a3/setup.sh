#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ libsqlite3-dev sqlite3
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # Create SQLite database
    sqlite3 org_chart.db <<EOF
CREATE TABLE nodes(id INTEGER PRIMARY KEY, parent_id INTEGER, name TEXT, role TEXT);
INSERT INTO nodes VALUES(1, NULL, 'Alice', 'CEO');
INSERT INTO nodes VALUES(2, 1, 'Bob', 'VP');
INSERT INTO nodes VALUES(3, 1, 'Charlie', 'VP');
INSERT INTO nodes VALUES(4, 2, 'Dave', 'Manager');
INSERT INTO nodes VALUES(5, 3, 'Eve', 'Manager');
INSERT INTO nodes VALUES(6, 4, 'Frank', 'Engineer');
EOF

    # Create C++ file
    cat << 'EOF' > fetch_team.cpp
#include <iostream>
#include <sqlite3.h>
#include <fstream>

int main() {
    sqlite3* db;
    if (sqlite3_open("/home/user/org_chart.db", &db)) return 1;

    // BROKEN QUERY
    const char* query = "SELECT n1.id, n1.name, n1.role FROM nodes n1, nodes n2 WHERE n1.parent_id = n2.id;";

    sqlite3_stmt* stmt;
    if (sqlite3_prepare_v2(db, query, -1, &stmt, nullptr) == SQLITE_OK) {
        std::ofstream out("/home/user/team_output.txt");
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            out << sqlite3_column_int(stmt, 0) << ","
                << sqlite3_column_text(stmt, 1) << ","
                << sqlite3_column_text(stmt, 2) << "\n";
        }
    }
    sqlite3_finalize(stmt);
    sqlite3_close(db);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
