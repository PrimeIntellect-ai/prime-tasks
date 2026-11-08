#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cd /home/user

    # Create SQLite database
    cat << 'EOF' > setup.sql
CREATE TABLE cities (id INTEGER PRIMARY KEY, name TEXT);
CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, city_id INTEGER);
CREATE TABLE purchases (id INTEGER PRIMARY KEY, user_id INTEGER, amount REAL);

INSERT INTO cities (id, name) VALUES (1, 'Seattle'), (2, 'Portland');

INSERT INTO users (id, name, city_id) VALUES (1, 'Alice', 1);
INSERT INTO users (id, name, city_id) VALUES (2, 'Bob', 1);
INSERT INTO users (id, name, city_id) VALUES (3, 'Charlie', 1);
INSERT INTO users (id, name, city_id) VALUES (4, 'David', 1);
INSERT INTO users (id, name, city_id) VALUES (5, 'Eve', 2);

INSERT INTO purchases (user_id, amount) VALUES (1, 150.50);
INSERT INTO purchases (user_id, amount) VALUES (1, 200.00);
INSERT INTO purchases (user_id, amount) VALUES (2, 50.25);
INSERT INTO purchases (user_id, amount) VALUES (3, 500.00);
INSERT INTO purchases (user_id, amount) VALUES (4, 300.00);
INSERT INTO purchases (user_id, amount) VALUES (4, 150.00);
EOF

    sqlite3 retail.db < setup.sql
    rm setup.sql

    # Create initial report.cpp
    cat << 'EOF' > report.cpp
#include <iostream>
#include <sqlite3.h>
#include <string>
#include <vector>
#include <map>
#include <algorithm>
#include <iomanip>

int main(int argc, char* argv[]) {
    if (argc != 2) return 1;
    std::string target_city = argv[1];

    sqlite3* db;
    if (sqlite3_open("retail.db", &db)) return 1;

    // Inefficient code goes here (omitted for brevity in setup, but agent rewrites it anyway)
    // The task requires rewriting this file to use a parameterized query.

    sqlite3_close(db);
    return 0;
}
EOF

    chmod -R 777 /home/user
