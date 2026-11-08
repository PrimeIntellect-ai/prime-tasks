#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        libsqlite3-dev \
        g++ \
        imagemagick \
        fonts-dejavu \
        sqlite3

    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /app

    # Create the image using ImageMagick
    # We need to modify policy.xml to allow text drawing if restricted, but usually it's fine for simple text.
    convert -size 900x100 xc:white -font DejaVu-Sans -pointsize 18 -fill black -draw "text 10,50 'MATCH (a:User)-[:FOLLOWS]->(b:User)-[:PURCHASED]->(c:Item) RETURN c.name ORDER BY c.name'" /app/query_pattern.png

    # Setup database
    cat << 'EOF' > /app/setup_db.py
import sqlite3
import random

db_path = '/home/user/data/graph.db'
conn = sqlite3.connect(db_path)
c = conn.cursor()
c.execute('CREATE TABLE nodes (id INTEGER PRIMARY KEY, name TEXT, label TEXT)')
c.execute('CREATE TABLE edges (src INTEGER, dst INTEGER, rel TEXT)')
c.execute('CREATE INDEX idx_edges_src ON edges(src)')

labels = ['User', 'Item', 'Category']
rels = ['FOLLOWS', 'PURCHASED', 'LIKES']

random.seed(42)
for i in range(1, 1001):
    c.execute('INSERT INTO nodes (id, name, label) VALUES (?, ?, ?)', (i, f'Node_{i}', random.choice(labels)))

for _ in range(5000):
    c.execute('INSERT INTO edges (src, dst, rel) VALUES (?, ?, ?)', (random.randint(1, 1000), random.randint(1, 1000), random.choice(rels)))

conn.commit()
conn.close()
EOF
    python3 /app/setup_db.py

    # Create oracle program
    cat << 'EOF' > /app/oracle_query_tool.cpp
#include <iostream>
#include <sqlite3.h>
#include <string>

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    sqlite3* db;
    if (sqlite3_open("/home/user/data/graph.db", &db)) return 1;

    std::string query = "SELECT c.name FROM nodes a JOIN edges e1 NOT INDEXED ON a.id = e1.src JOIN nodes b ON e1.dst = b.id JOIN edges e2 NOT INDEXED ON b.id = e2.src JOIN nodes c ON e2.dst = c.id WHERE a.id = ? AND a.label = 'User' AND e1.rel = 'FOLLOWS' AND b.label = 'User' AND e2.rel = 'PURCHASED' AND c.label = 'Item' ORDER BY c.name;";

    sqlite3_stmt* stmt;
    if (sqlite3_prepare_v2(db, query.c_str(), -1, &stmt, nullptr) != SQLITE_OK) {
        std::cerr << sqlite3_errmsg(db) << std::endl;
        return 1;
    }

    sqlite3_bind_int(stmt, 1, std::stoi(argv[1]));

    while (sqlite3_step(stmt) == SQLITE_ROW) {
        std::cout << sqlite3_column_text(stmt, 0) << std::endl;
    }

    sqlite3_finalize(stmt);
    sqlite3_close(db);
    return 0;
}
EOF
    g++ /app/oracle_query_tool.cpp -o /app/oracle_query_tool -lsqlite3

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
