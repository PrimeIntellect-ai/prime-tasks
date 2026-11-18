#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev g++ nlohmann-json3-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    # Create SQLite DB
    sqlite3 /home/user/research_data.db <<EOF
CREATE TABLE institutions (id INTEGER PRIMARY KEY, name TEXT);
CREATE TABLE authors (id INTEGER PRIMARY KEY, name TEXT, institution_id INTEGER);
CREATE TABLE papers (id INTEGER PRIMARY KEY, title TEXT);
CREATE TABLE authorships (author_id INTEGER, paper_id INTEGER);
CREATE TABLE citations (citing_paper_id INTEGER, cited_paper_id INTEGER);

INSERT INTO institutions VALUES (1, 'Tech University'), (2, 'State College');
INSERT INTO authors VALUES (101, 'Dr. Alpha', 1), (102, 'Dr. Bravo', 1), (103, 'Dr. Charlie', 2);
INSERT INTO papers VALUES (201, 'Paper A1'), (202, 'Paper A2'), (203, 'Paper B1'), (204, 'Paper C1');
INSERT INTO authorships VALUES (101, 201), (101, 202), (102, 203), (103, 204);

-- Citations
INSERT INTO citations VALUES (901, 201), (902, 201), (903, 201); -- 3 for 201 (Alpha)
INSERT INTO citations VALUES (904, 202), (905, 202); -- 2 for 202 (Alpha) -> Total Alpha = 5
INSERT INTO citations VALUES (906, 203); -- 1 for 203 (Bravo) -> Total Bravo = 1
INSERT INTO citations VALUES (907, 204), (908, 204), (909, 204), (910, 204); -- 4 for 204 (Charlie) -> Total Charlie = 4
EOF

    # Create buggy C++ program
    cat << 'EOF' > /home/user/metrics.cpp
#include <iostream>
#include <fstream>
#include <sqlite3.h>
#include <nlohmann/json.hpp>

using json = nlohmann::json;

int main() {
    sqlite3* db;
    if (sqlite3_open("/home/user/research_data.db", &db)) return 1;

    // BUGGY QUERY: Implicit cross join on citations, missing window function
    const char* sql = R"(
        SELECT a.id, a.name, i.name, COUNT(c.cited_paper_id) as total_citations, 1 as institution_rank
        FROM authors a, institutions i, authorships ash, papers p, citations c
        WHERE a.institution_id = i.id 
          AND a.id = ash.author_id 
          AND ash.paper_id = p.id
        GROUP BY a.id, a.name, i.name
        ORDER BY total_citations DESC, a.id ASC
    )";

    sqlite3_stmt* stmt;
    sqlite3_prepare_v2(db, sql, -1, &stmt, nullptr);

    json output = json::array();
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        output.push_back({
            {"author_id", sqlite3_column_int(stmt, 0)},
            {"author_name", reinterpret_cast<const char*>(sqlite3_column_text(stmt, 1))},
            {"institution_name", reinterpret_cast<const char*>(sqlite3_column_text(stmt, 2))},
            {"total_citations", sqlite3_column_int(stmt, 3)},
            {"institution_rank", sqlite3_column_int(stmt, 4)}
        });
    }

    sqlite3_finalize(stmt);
    sqlite3_close(db);

    std::ofstream out("/home/user/metrics_output.json");
    out << output.dump(2);
    return 0;
}
EOF

    chmod -R 777 /home/user
