#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup_db.py
import sqlite3

conn = sqlite3.connect('/home/user/research_data.db')
c = conn.cursor()

c.execute('CREATE TABLE datasets (id INTEGER PRIMARY KEY, title TEXT)')
c.execute('CREATE TABLE authors (id INTEGER PRIMARY KEY, name TEXT)')
c.execute('CREATE TABLE dataset_authors (dataset_id INTEGER, author_id INTEGER)')

datasets = [
    (1, "Quantum Entanglement Set"),
    (2, "Photon Emission Data"),
    (3, "Subatomic Scattering"),
    (4, "Standard Model Results"),
    (5, "Macroscopic Superposition Set"),
    (6, "Irrelevant Data A"),
    (7, "Irrelevant Data B")
]
c.executemany('INSERT INTO datasets VALUES (?, ?)', datasets)

authors = [
    (1, "Alice"),
    (2, "Bob"),
    (3, "Charlie"),
    (4, "Dave"),
    (5, "Eve")
]
c.executemany('INSERT INTO authors VALUES (?, ?)', authors)

# Path: Quantum -> Photon -> Subatomic -> Standard -> Macroscopic
# Quantum (1) shares Alice (1) with Photon (2)
# Photon (2) shares Bob (2) with Subatomic (3)
# Subatomic (3) shares Charlie (3) with Standard (4)
# Standard (4) shares Dave (4) with Macroscopic (5)
# Eve (5) is isolated on Irrelevant Data
relations = [
    (1, 1), (2, 1), # Alice on 1 and 2
    (2, 2), (3, 2), # Bob on 2 and 3
    (3, 3), (4, 3), # Charlie on 3 and 4
    (4, 4), (5, 4), # Dave on 4 and 5
    (6, 5), (7, 5)  # Eve on 6 and 7
]
c.executemany('INSERT INTO dataset_authors VALUES (?, ?)', relations)

conn.commit()
conn.close()
EOF
    python3 /home/user/setup_db.py

    cat << 'EOF' > /home/user/graph_search.cpp
#include <iostream>
#include <sqlite3.h>
#include <string>
#include <vector>
#include <queue>
#include <unordered_map>
#include <unordered_set>

std::string getTitle(sqlite3* db, int id) {
    std::string title = "";
    std::string query = "SELECT title FROM datasets WHERE id = " + std::to_string(id) + ";";
    sqlite3_stmt* stmt;
    if (sqlite3_prepare_v2(db, query.c_str(), -1, &stmt, NULL) == SQLITE_OK) {
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            title = reinterpret_cast<const char*>(sqlite3_column_text(stmt, 0));
        }
    }
    sqlite3_finalize(stmt);
    return title;
}

int getId(sqlite3* db, const std::string& title) {
    int id = -1;
    std::string query = "SELECT id FROM datasets WHERE title = '" + title + "';";
    sqlite3_stmt* stmt;
    if (sqlite3_prepare_v2(db, query.c_str(), -1, &stmt, NULL) == SQLITE_OK) {
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            id = sqlite3_column_int(stmt, 0);
        }
    }
    sqlite3_finalize(stmt);
    return id;
}

int main(int argc, char** argv) {
    if (argc != 3) {
        std::cerr << "Usage: ./graph_search <start_dataset> <end_dataset>\n";
        return 1;
    }

    std::string start_title = argv[1];
    std::string end_title = argv[2];

    sqlite3* db;
    if (sqlite3_open("/home/user/research_data.db", &db)) {
        return 1;
    }

    int start_id = getId(db, start_title);
    int end_id = getId(db, end_title);

    if (start_id == -1 || end_id == -1) {
        std::cerr << "Dataset not found.\n";
        return 1;
    }

    std::queue<int> q;
    std::unordered_map<int, int> parent;
    std::unordered_set<int> visited;

    q.push(start_id);
    visited.insert(start_id);
    parent[start_id] = -1;

    bool found = false;

    while (!q.empty()) {
        int curr = q.front();
        q.pop();

        if (curr == end_id) {
            found = true;
            break;
        }

        // BUGGY QUERY: implicit cross join! Needs to be fixed to find datasets sharing authors.
        // Also needs parameterization.
        std::string query = "SELECT b.dataset_id FROM dataset_authors a, dataset_authors b;"; 

        sqlite3_stmt* stmt;
        if (sqlite3_prepare_v2(db, query.c_str(), -1, &stmt, NULL) == SQLITE_OK) {
            while (sqlite3_step(stmt) == SQLITE_ROW) {
                int neighbor = sqlite3_column_int(stmt, 0);
                if (visited.find(neighbor) == visited.end()) {
                    visited.insert(neighbor);
                    parent[neighbor] = curr;
                    q.push(neighbor);
                }
            }
        }
        sqlite3_finalize(stmt);
    }

    if (found) {
        std::vector<int> path;
        int curr = end_id;
        while (curr != -1) {
            path.push_back(curr);
            curr = parent[curr];
        }
        for (int i = path.size() - 1; i >= 0; --i) {
            std::cout << getTitle(db, path[i]);
            if (i > 0) std::cout << ",";
        }
        std::cout << "\n";
    } else {
        std::cout << "No path found.\n";
    }

    sqlite3_close(db);
    return 0;
}
EOF

    chmod -R 777 /home/user
