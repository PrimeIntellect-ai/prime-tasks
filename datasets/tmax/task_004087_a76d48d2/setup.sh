#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev g++
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # Create the SQLite database
    sqlite3 graph.db <<EOF
CREATE TABLE Nodes (id INTEGER PRIMARY KEY, name TEXT);
CREATE TABLE Edges (src INTEGER, dst INTEGER, type TEXT);

INSERT INTO Nodes VALUES (1, 'Alice');
INSERT INTO Nodes VALUES (2, 'Bob');
INSERT INTO Nodes VALUES (3, 'Charlie');
INSERT INTO Nodes VALUES (4, 'David');
INSERT INTO Nodes VALUES (5, 'Eve');
INSERT INTO Nodes VALUES (6, 'Frank');

-- Edges
INSERT INTO Edges VALUES (1, 2, 'friend');
INSERT INTO Edges VALUES (2, 3, 'friend');
INSERT INTO Edges VALUES (1, 3, 'friend'); -- Direct connection exists, so 1->3 should be filtered out from 2nd degree
INSERT INTO Edges VALUES (3, 4, 'friend');
INSERT INTO Edges VALUES (4, 5, 'friend');
INSERT INTO Edges VALUES (2, 5, 'friend'); -- 2->3->4, 2->4 is valid. 2->5 is direct, so 3->4->5 -> 3->5 is valid. Wait, 2->5 is direct.
INSERT INTO Edges VALUES (5, 6, 'friend');
EOF

    # Create the buggy C++ file
    cat << 'EOF' > /home/user/project_graph.cpp
#include <iostream>
#include <fstream>
#include <sqlite3.h>
#include <string>

int main() {
    sqlite3* db;
    if (sqlite3_open("/home/user/graph.db", &db)) {
        return 1;
    }

    // BUGGY QUERY: Implicit cross join, no pagination, no proper filtering
    std::string query = "SELECT N1.id, N2.id FROM Nodes N1, Nodes N2, Edges E1, Edges E2 WHERE E1.type='friend'";

    std::ofstream out("/home/user/output.csv");
    out << "src,dst\n";

    sqlite3_stmt* stmt;
    if (sqlite3_prepare_v2(db, query.c_str(), -1, &stmt, nullptr) == SQLITE_OK) {
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            out << sqlite3_column_int(stmt, 0) << "," << sqlite3_column_int(stmt, 1) << "\n";
        }
        sqlite3_finalize(stmt);
    }

    sqlite3_close(db);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
