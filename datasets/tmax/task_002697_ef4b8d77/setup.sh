#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        sqlite3 \
        libsqlite3-dev \
        g++ \
        make

    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/leaky_processor.cpp
#include <iostream>
#include <sqlite3.h>
#include <string>
#include <vector>
#include <fstream>
#include <sstream>

std::string process_payload(const std::string& hex_str) {
    if (hex_str.length() % 2 != 0) {
        char* leak = new char[1024*1024]; // Memory leak
        throw std::runtime_error("Odd length");
    }
    std::string res = "";
    for (size_t i = 0; i < hex_str.length(); i += 2) {
        std::string byteString = hex_str.substr(i, 2);
        char byte = (char) strtol(byteString.c_str(), NULL, 16);
        res += (char)(byte ^ 0x5A);
    }
    return res;
}

int main(int argc, char** argv) {
    if (argc < 3) return 1;
    sqlite3* db;
    if (sqlite3_open(argv[1], &db)) return 1;

    sqlite3_stmt* stmt;
    sqlite3_prepare_v2(db, "SELECT id, payload FROM records", -1, &stmt, NULL);

    std::ofstream out(argv[2]);
    out << "{";
    bool first = true;
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        int id = sqlite3_column_int(stmt, 0);
        const unsigned char* payload = sqlite3_column_text(stmt, 1);
        if (!payload) continue;
        try {
            std::string transformed = process_payload((const char*)payload);
            if (!first) out << ",";
            out << "\"" << id << "\":\"" << transformed << "\"";
            first = false;
        } catch (...) {
            continue;
        }
    }
    out << "}";
    sqlite3_finalize(stmt);
    sqlite3_close(db);
    return 0;
}
EOF

    g++ -O2 /app/leaky_processor.cpp -o /app/leaky_processor -lsqlite3
    strip /app/leaky_processor
    rm /app/leaky_processor.cpp

    mkdir -p /home/user/data
    python3 -c '
import sqlite3
conn = sqlite3.connect("/home/user/data/events.db")
c = conn.cursor()
c.execute("CREATE TABLE records (id INTEGER PRIMARY KEY, payload TEXT)")
c.execute("INSERT INTO records (id, payload) VALUES (1, \"323f363635\")")
c.execute("INSERT INTO records (id, payload) VALUES (2, \"123\")")
conn.commit()
conn.close()
'

    # Corrupt the database header
    dd if=/dev/urandom of=/home/user/data/events.db bs=1 count=16 conv=notrunc

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
