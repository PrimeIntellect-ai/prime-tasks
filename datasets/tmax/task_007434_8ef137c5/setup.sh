#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create database initialization script
    cat << 'EOF' > /home/user/setup_db.sql
CREATE TABLE Nodes (id INTEGER PRIMARY KEY, value INTEGER);
CREATE TABLE Edges (source_id INTEGER, target_id INTEGER, weight INTEGER);

INSERT INTO Nodes (id, value) VALUES (1, 0), (2, 0), (3, 0), (4, 0), (5, 0);
INSERT INTO Edges (source_id, target_id, weight) VALUES 
(1, 3, 10), (3, 4, 5), (4, 5, 2),
(2, 4, 15), (4, 5, 2);
EOF

    # Initialize the database
    sqlite3 /home/user/graph.db < /home/user/setup_db.sql

    # Create the buggy pipeline.cpp
    cat << 'EOF' > /home/user/pipeline.cpp
#include <iostream>
#include <sqlite3.h>
#include <thread>
#include <vector>
#include <string>
#include <chrono>

void process_node(int start_node) {
    sqlite3* db;
    if (sqlite3_open("/home/user/graph.db", &db) != SQLITE_OK) return;

    // BUG: Deferred transaction leads to deadlock when multiple threads read then write
    sqlite3_exec(db, "BEGIN;", 0, 0, 0);

    const char* query = 
        "WITH RECURSIVE traverse(id) AS ("
        "  SELECT target_id FROM Edges WHERE source_id = ? "
        "  UNION "
        "  SELECT Edges.target_id FROM Edges JOIN traverse ON Edges.source_id = traverse.id"
        ") "
        "SELECT SUM(weight) FROM Edges WHERE source_id IN traverse;";

    sqlite3_stmt* stmt;
    sqlite3_prepare_v2(db, query, -1, &stmt, 0);
    sqlite3_bind_int(stmt, 1, start_node);

    int total_weight = 0;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        total_weight = sqlite3_column_int(stmt, 0);
    }
    sqlite3_finalize(stmt);

    // Force a small delay to guarantee a race condition / deadlock with default BEGIN
    std::this_thread::sleep_for(std::chrono::milliseconds(500));

    std::string update_query = "UPDATE Nodes SET value = " + std::to_string(total_weight) + 
                               " WHERE id = " + std::to_string(start_node) + ";";

    char* err = nullptr;
    if (sqlite3_exec(db, update_query.c_str(), 0, 0, &err) != SQLITE_OK) {
        std::cerr << "Error updating node " << start_node << ": " << err << std::endl;
        sqlite3_free(err);
    }

    sqlite3_exec(db, "COMMIT;", 0, 0, 0);
    sqlite3_close(db);
}

int main() {
    sqlite3_config(SQLITE_CONFIG_MULTITHREAD);
    std::thread t1(process_node, 1);
    std::thread t2(process_node, 2);

    t1.join();
    t2.join();

    // TODO: Query final nodes and write to /home/user/final_nodes.csv
    return 0;
}
EOF

    chmod -R 777 /home/user
