#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev g++
    pip3 install pytest

    mkdir -p /home/user/audit_tool
    cd /home/user

    # Create database
    sqlite3 compliance.db <<EOF
PRAGMA journal_mode=WAL;
CREATE TABLE accounts (id INTEGER PRIMARY KEY, risk_score INTEGER);
CREATE TABLE transactions (id INTEGER PRIMARY KEY, account_id INTEGER, sender_id INTEGER, receiver_id INTEGER, amount REAL, timestamp INTEGER);

INSERT INTO accounts (id, risk_score) VALUES (101, 0), (102, 0), (103, 0), (205, 0), (999, 0);

-- Data for index testing
INSERT INTO transactions (account_id, sender_id, receiver_id, amount, timestamp) VALUES
(101, 101, 102, 50.0, 1600000000),
(102, 102, 103, 50.0, 1600000001),
(103, 103, 205, 50.0, 1600000002),
(101, 101, 999, 10.0, 1600000003),
(999, 999, 205, 10.0, 1600000004);
EOF

    # Create C++ deadlock file
    cat << 'EOF' > /home/user/audit_tool/main.cpp
#include <iostream>
#include <sqlite3.h>
#include <thread>
#include <chrono>
#include <fstream>

void update_account(sqlite3* db, int id, int risk) {
    std::string sql = "UPDATE accounts SET risk_score = risk_score + " + std::to_string(risk) + " WHERE id = " + std::to_string(id) + ";";
    sqlite3_exec(db, sql.c_str(), 0, 0, 0);
}

void thread_a() {
    sqlite3* db;
    sqlite3_open("/home/user/compliance.db", &db);
    sqlite3_exec(db, "BEGIN EXCLUSIVE;", 0, 0, 0);
    update_account(db, 101, 10);
    std::this_thread::sleep_for(std::chrono::milliseconds(500));
    update_account(db, 102, 10);
    sqlite3_exec(db, "COMMIT;", 0, 0, 0);
    sqlite3_close(db);
}

void thread_b() {
    sqlite3* db;
    sqlite3_open("/home/user/compliance.db", &db);
    sqlite3_exec(db, "BEGIN EXCLUSIVE;", 0, 0, 0);
    update_account(db, 102, 20);
    std::this_thread::sleep_for(std::chrono::milliseconds(500));
    update_account(db, 101, 20);
    sqlite3_exec(db, "COMMIT;", 0, 0, 0);
    sqlite3_close(db);
}

int main() {
    sqlite3_config(SQLITE_CONFIG_MULTITHREAD);
    std::thread t1(thread_a);
    std::thread t2(thread_b);
    t1.join();
    t2.join();

    std::ofstream out("audit_success.log");
    out << "AUDIT_COMPLETE";
    out.close();
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
