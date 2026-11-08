#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc g++ sqlite3 libsqlite3-dev
    pip3 install pytest

    mkdir -p /home/user/src
    mkdir -p /home/user/build

    cat << 'EOF' > /home/user/src/libcompute.c
int compute_hash(int val) {
    return val * 42;
}
EOF

    cat << 'EOF' > /home/user/src/main.cpp
#include <iostream>
#include <sqlite3.h>

extern "C" {
    int compute_hash(int);
}

int main(int argc, char** argv) {
    if (argc < 2) {
        std::cerr << "Missing database path" << std::endl;
        return 1;
    }

    sqlite3* db;
    if (sqlite3_open(argv[1], &db) != SQLITE_OK) {
        std::cerr << "Failed to open DB" << std::endl;
        return 1;
    }

    sqlite3_stmt* stmt;
    if (sqlite3_prepare_v2(db, "SELECT value FROM config WHERE id = 1", -1, &stmt, nullptr) != SQLITE_OK) {
        std::cerr << "Failed to prepare statement" << std::endl;
        return 1;
    }

    if (sqlite3_step(stmt) == SQLITE_ROW) {
        int val = sqlite3_column_int(stmt, 0);
        std::cout << "MIGRATED_HASH=" << compute_hash(val) << std::endl;
    } else {
        std::cout << "MIGRATED_HASH=ERROR" << std::endl;
    }

    sqlite3_finalize(stmt);
    sqlite3_close(db);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/src/schema_v1.sql
CREATE TABLE config (id INTEGER PRIMARY KEY, value INTEGER);
INSERT INTO config (value) VALUES (10);
EOF

    cat << 'EOF' > /home/user/src/migration_v2.sql
UPDATE config SET value = 15 WHERE id = 1;
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
