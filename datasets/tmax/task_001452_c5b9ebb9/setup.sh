#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ libsqlite3-dev nlohmann-json3-dev
    pip3 install pytest

    mkdir -p /app
    useradd -m -s /bin/bash user || true

    # Create C++ program
    cat << 'EOF' > /tmp/graph_materializer.cpp
#include <iostream>
#include <string>
#include <sqlite3.h>
#include <nlohmann/json.hpp>

using json = nlohmann::json;

int main() {
    std::string input((std::istreambuf_iterator<char>(std::cin)), std::istreambuf_iterator<char>());
    if (input.empty()) return 0;

    json j;
    try {
        j = json::parse(input);
    } catch (...) { return 1; }

    std::string source = j.contains("source_table") ? j["source_table"].get<std::string>() : j.value("source", "");
    std::string target = j.contains("target_table") ? j["target_table"].get<std::string>() : j.value("target", "");
    std::string link = j.contains("relation_type") ? j["relation_type"].get<std::string>() : j.value("link", "");

    sqlite3* db;
    if (sqlite3_open("/home/user/data.db", &db) != SQLITE_OK) return 1;

    std::string query = "";
    if (source == "Users" && target == "Departments") {
        query = "SELECT Users.id, Departments.id, '" + link + "' FROM Users JOIN Departments ON Users.dept_id = Departments.id;";
    } else if (source == "Users" && target == "Roles") {
        query = "SELECT Users.id, Roles.id, '" + link + "' FROM Users JOIN UserRoles ON Users.id = UserRoles.user_id JOIN Roles ON UserRoles.role_id = Roles.id;";
    } else if (source == "Users" && target == "Projects") {
        query = "SELECT Users.id, Projects.id, '" + link + "' FROM Users JOIN Projects ON Users.id = Projects.owner_id;";
    } else {
        sqlite3_close(db);
        return 0;
    }

    sqlite3_stmt* stmt;
    if (sqlite3_prepare_v2(db, query.c_str(), -1, &stmt, nullptr) == SQLITE_OK) {
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            std::cout << sqlite3_column_text(stmt, 0) << ","
                      << sqlite3_column_text(stmt, 1) << ","
                      << sqlite3_column_text(stmt, 2) << "\n";
        }
        sqlite3_finalize(stmt);
    }
    sqlite3_close(db);
    return 0;
}
EOF

    g++ -O2 -s /tmp/graph_materializer.cpp -o /app/graph_materializer_bin -lsqlite3
    rm /tmp/graph_materializer.cpp

    # Populate database
    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import random

db = sqlite3.connect('/home/user/data.db')
c = db.cursor()
c.execute('CREATE TABLE Departments(id INTEGER PRIMARY KEY, name TEXT)')
c.execute('CREATE TABLE Roles(id INTEGER PRIMARY KEY, title TEXT)')
c.execute('CREATE TABLE Users(id INTEGER PRIMARY KEY, name TEXT, dept_id INTEGER)')
c.execute('CREATE TABLE UserRoles(user_id INTEGER, role_id INTEGER)')
c.execute('CREATE TABLE Projects(id INTEGER PRIMARY KEY, name TEXT, owner_id INTEGER)')

for i in range(1, 11):
    c.execute('INSERT INTO Departments VALUES (?, ?)', (i, f'Dept{i}'))
    c.execute('INSERT INTO Roles VALUES (?, ?)', (i, f'Role{i}'))

for i in range(1, 501):
    c.execute('INSERT INTO Users VALUES (?, ?, ?)', (i, f'User{i}', random.randint(1, 10)))
    c.execute('INSERT INTO UserRoles VALUES (?, ?)', (i, random.randint(1, 10)))
    c.execute('INSERT INTO Projects VALUES (?, ?, ?)', (i, f'Proj{i}', random.randint(1, 500)))

db.commit()
db.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
