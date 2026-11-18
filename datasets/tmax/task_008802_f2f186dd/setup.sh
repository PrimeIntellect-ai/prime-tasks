#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3

conn = sqlite3.connect('/home/user/dataset.db')
c = conn.cursor()

c.execute('CREATE TABLE authors (id INTEGER PRIMARY KEY, name TEXT)')
c.execute('CREATE TABLE papers (id INTEGER PRIMARY KEY, title TEXT)')
c.execute('CREATE TABLE author_paper (author_id INTEGER, paper_id INTEGER)')
c.execute('CREATE TABLE citations (cited_paper_id INTEGER, count INTEGER)')

authors = [(1, 'Alice'), (2, 'Bob'), (3, 'Charlie'), (4, 'David'), (5, 'Eve')]
papers = [(1, 'Paper A'), (2, 'Paper B'), (3, 'Paper C'), (4, 'Paper D'), (5, 'Paper E')]
# Alice coauthors with Bob (P1) and David (P4)
# Bob coauthors with Charlie (P2)
# Charlie coauthors with David (P3)
# Eve is solo (P5)
author_paper = [
    (1, 1), (2, 1), # P1: Alice, Bob
    (2, 2), (3, 2), # P2: Bob, Charlie
    (3, 3), (4, 3), # P3: Charlie, David
    (1, 4), (4, 4), # P4: Alice, David
    (5, 5)          # P5: Eve
]
citations = [(1, 10), (2, 20), (3, 5), (4, 15), (5, 50)]

c.executemany('INSERT INTO authors VALUES (?,?)', authors)
c.executemany('INSERT INTO papers VALUES (?,?)', papers)
c.executemany('INSERT INTO author_paper VALUES (?,?)', author_paper)
c.executemany('INSERT INTO citations VALUES (?,?)', citations)

conn.commit()
conn.close()
EOF
    python3 /tmp/setup_db.py

    cat << 'EOF' > /home/user/metrics.cpp
#include <iostream>
#include <fstream>
#include <sqlite3.h>
#include <string>

int main() {
    sqlite3* db;
    if (sqlite3_open("/home/user/dataset.db", &db)) return 1;

    // BUGGY QUERY: Missing join condition between a2 and ap3 causes cross join
    std::string sql = R"(
        SELECT 
            a1.name,
            COUNT(DISTINCT a2.id) as coauthor_count,
            SUM(c.count) as coauthor_citations
        FROM authors a1
        JOIN author_paper ap1 ON a1.id = ap1.author_id
        JOIN author_paper ap2 ON ap1.paper_id = ap2.paper_id AND a1.id != ap2.author_id
        JOIN authors a2 -- Missing condition: ON ap2.author_id = a2.id
        JOIN author_paper ap3 -- Cross join happens here
        JOIN citations c ON ap3.paper_id = c.cited_paper_id
        GROUP BY a1.id
        ORDER BY coauthor_citations DESC, a1.name ASC
        LIMIT 10;
    )";

    sqlite3_stmt* stmt;
    if (sqlite3_prepare_v2(db, sql.c_str(), -1, &stmt, nullptr) != SQLITE_OK) return 1;

    std::ofstream out("/home/user/top_coauthor_metrics.txt");
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        out << sqlite3_column_text(stmt, 0) << "|"
            << sqlite3_column_int(stmt, 1) << "|"
            << sqlite3_column_int(stmt, 2) << "\n";
    }

    sqlite3_finalize(stmt);
    sqlite3_close(db);
    return 0;
}
EOF

    chown -R user:user /home/user/dataset.db /home/user/metrics.cpp
    chmod -R 777 /home/user
