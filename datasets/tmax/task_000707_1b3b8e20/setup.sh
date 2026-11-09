#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev libssl-dev g++ wget curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/src /home/user/data

    # Download cpp-httplib header
    wget -qO /home/user/src/httplib.h https://raw.githubusercontent.com/yhirose/cpp-httplib/v0.14.1/httplib.h

    # Create SQLite database and populate with test user
    sqlite3 /home/user/data/users.db "CREATE TABLE users (username TEXT, password_hash TEXT);"
    sqlite3 /home/user/data/users.db "INSERT INTO users (username, password_hash) VALUES ('admin', '8c6976e5b5410415bde908bd4dee15dfb167a9c873fc4bb8a81f6f2ab448a918');"

    # Create vulnerable server.cpp
    cat << 'EOF' > /home/user/src/server.cpp
#include "httplib.h"
#include <sqlite3.h>
#include <iostream>
#include <string>

// Weak custom checksum
std::string weak_hash(const std::string& input) {
    return input; // Plaintext for demonstration of vulnerability
}

int main() {
    httplib::Server svr;

    svr.Post("/login", [](const httplib::Request& req, httplib::Response& res) {
        std::string username = req.get_param_value("username");
        std::string password = req.get_param_value("password");

        sqlite3* db;
        if (sqlite3_open("/home/user/data/users.db", &db) != SQLITE_OK) {
            res.status = 500;
            return;
        }

        // VULNERABILITY 1: SQL Injection
        std::string query = "SELECT password_hash FROM users WHERE username = '" + username + "'";
        sqlite3_stmt* stmt;
        std::string db_hash = "";

        if (sqlite3_prepare_v2(db, query.c_str(), -1, &stmt, nullptr) == SQLITE_OK) {
            if (sqlite3_step(stmt) == SQLITE_ROW) {
                db_hash = reinterpret_cast<const char*>(sqlite3_column_text(stmt, 0));
            }
        }
        sqlite3_finalize(stmt);
        sqlite3_close(db);

        // VULNERABILITY 2: Weak Cryptography
        if (!db_hash.empty() && weak_hash(password) == db_hash) {
            // VULNERABILITY 3: Insecure Cookie
            res.set_header("Set-Cookie", "session_id=123456789");
            res.set_content("Login successful", "text/plain");
        } else {
            res.status = 401;
            res.set_content("Unauthorized", "text/plain");
        }
    });

    svr.Get("/greet", [](const httplib::Request& req, httplib::Response& res) {
        std::string name = req.has_param("name") ? req.get_param_value("name") : "Guest";
        // VULNERABILITY 4: Reflected XSS
        res.set_content("<html><body><h1>Hello, " + name + "</h1></body></html>", "text/html");
    });

    svr.listen("127.0.0.1", 8080);
    return 0;
}
EOF

    chmod -R 777 /home/user
