#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    apt-get install -y sqlite3 libsqlite3-dev g++

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/network.db <<EOF
CREATE TABLE edges (source TEXT, target TEXT);
INSERT INTO edges VALUES ('Service_A', 'Service_B');
INSERT INTO edges VALUES ('Service_A', 'Service_C');
INSERT INTO edges VALUES ('Service_B', 'Service_D');
INSERT INTO edges VALUES ('Service_C', 'Service_D');
INSERT INTO edges VALUES ('Service_D', 'Service_E');
INSERT INTO edges VALUES ('Service_C', 'Service_F');
INSERT INTO edges VALUES ('Service_E', 'Service_G');
INSERT INTO edges VALUES ('Service_F', 'Service_E');
EOF

    cat << 'EOF' > /home/user/db_traversal.cpp
#include <iostream>
#include <fstream>
#include <sqlite3.h>
#include <string>

int main() {
    sqlite3* db;
    int rc = sqlite3_open("/home/user/network.db", &db);
    if (rc) {
        std::cerr << "Can't open database: " << sqlite3_errmsg(db) << std::endl;
        return 1;
    }

    // TODO: Write your recursive CTE query here
    std::string sql = ""; 

    std::ofstream logfile("/home/user/optimized_paths.log");

    sqlite3_stmt* stmt;
    rc = sqlite3_prepare_v2(db, sql.c_str(), -1, &stmt, nullptr);
    if (rc != SQLITE_OK) {
        std::cerr << "Failed to prepare statement: " << sqlite3_errmsg(db) << std::endl;
        return 1;
    }

    // TODO: Step through the results and write to logfile
    // Format: "Node: " << name << ", Shortest Depth: " << depth << "\n"

    sqlite3_finalize(stmt);
    sqlite3_close(db);
    return 0;
}
EOF

    chmod -R 777 /home/user
