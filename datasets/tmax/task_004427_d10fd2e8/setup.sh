#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ sqlite3 libsqlite3-dev
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/generator.cpp
#include <sqlite3.h>
#include <iostream>
#include <vector>
#include <string>
#include <random>

int main() {
    sqlite3* db;
    if (sqlite3_open("graph.db", &db)) return 1;

    sqlite3_exec(db, "PRAGMA synchronous = OFF; PRAGMA journal_mode = MEMORY;", 0, 0, 0);
    sqlite3_exec(db, "CREATE TABLE Nodes (id INTEGER PRIMARY KEY, type TEXT, value REAL);", 0, 0, 0);
    sqlite3_exec(db, "CREATE TABLE Edges (source INTEGER, target INTEGER, weight REAL);", 0, 0, 0);

    sqlite3_exec(db, "BEGIN TRANSACTION;", 0, 0, 0);

    sqlite3_stmt* stmt;
    sqlite3_prepare_v2(db, "INSERT INTO Nodes (id, type, value) VALUES (?, ?, ?);", -1, &stmt, 0);

    std::mt19937 gen(42); // Deterministic seed
    std::uniform_real_distribution<> val_dist(0.0, 100.0);
    std::uniform_int_distribution<> type_dist(0, 99);

    for (int i = 1; i <= 50000; ++i) {
        int t = type_dist(gen);
        std::string type;
        if (t < 10) type = "AUTHOR";
        else if (t < 50) type = "ARTICLE";
        else if (t < 70) type = "VENUE";
        else type = "INSTITUTION";

        sqlite3_bind_int(stmt, 1, i);
        sqlite3_bind_text(stmt, 2, type.c_str(), -1, SQLITE_TRANSIENT);
        sqlite3_bind_double(stmt, 3, val_dist(gen));
        sqlite3_step(stmt);
        sqlite3_reset(stmt);
    }
    sqlite3_finalize(stmt);

    sqlite3_prepare_v2(db, "INSERT INTO Edges (source, target, weight) VALUES (?, ?, ?);", -1, &stmt, 0);
    std::uniform_int_distribution<> node_dist(1, 50000);
    std::uniform_real_distribution<> weight_dist(0.0, 1.0);

    for (int i = 0; i < 200000; ++i) {
        sqlite3_bind_int(stmt, 1, node_dist(gen));
        sqlite3_bind_int(stmt, 2, node_dist(gen));
        sqlite3_bind_double(stmt, 3, weight_dist(gen));
        sqlite3_step(stmt);
        sqlite3_reset(stmt);
    }
    sqlite3_finalize(stmt);

    sqlite3_exec(db, "COMMIT;", 0, 0, 0);
    sqlite3_close(db);
    return 0;
}
EOF

    g++ -O3 /app/generator.cpp -lsqlite3 -o /app/data_generator
    strip /app/data_generator
    rm /app/generator.cpp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
