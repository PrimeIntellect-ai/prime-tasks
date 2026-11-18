#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make sqlite3 libsqlite3-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/auth_service
    cd /home/user/auth_service

    # Create initial SQLite DB
    sqlite3 db.sqlite "CREATE TABLE users (id INTEGER PRIMARY KEY, username TEXT, password TEXT);"
    sqlite3 db.sqlite "INSERT INTO users (username, password) VALUES ('admin', 'password123');"
    sqlite3 db.sqlite "INSERT INTO users (username, password) VALUES ('guest', 'guestpass');"

    # Create Makefile
    cat << 'EOF' > Makefile
CXX = g++
CXXFLAGS = -Wall -Wextra -std=c++17
LDFLAGS = -lsqlite3

auth_api: auth_api.cpp
	$(CXX) $(CXXFLAGS) auth_api.cpp -o auth_api $(LDFLAGS)

clean:
	rm -f auth_api
EOF

    # Create vulnerable C++ file
    cat << 'EOF' > auth_api.cpp
#include <iostream>
#include <string>
#include <sqlite3.h>

bool authenticate_user(sqlite3* db, const std::string& username, const std::string& password) {
    std::string query = "SELECT id FROM users WHERE username = '" + username + "' AND password = '" + password + "';";
    sqlite3_stmt* stmt;

    if (sqlite3_prepare_v2(db, query.c_str(), -1, &stmt, nullptr) != SQLITE_OK) {
        std::cerr << "Database error: " << sqlite3_errmsg(db) << std::endl;
        return false;
    }

    bool authenticated = false;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        authenticated = true;
    }

    sqlite3_finalize(stmt);
    return authenticated;
}

int main(int argc, char* argv[]) {
    if (argc != 3) {
        std::cerr << "Usage: " << argv[0] << " <username> <password>" << std::endl;
        return 1;
    }

    sqlite3* db;
    if (sqlite3_open("db.sqlite", &db) != SQLITE_OK) {
        std::cerr << "Failed to open database." << std::endl;
        return 1;
    }

    if (authenticate_user(db, argv[1], argv[2])) {
        std::cout << "LOGIN_SUCCESS" << std::endl;
    } else {
        std::cout << "LOGIN_FAILED" << std::endl;
    }

    sqlite3_close(db);
    return 0;
}
EOF

    # Create test script
    cat << 'EOF' > test_auth.sh
#!/bin/bash
echo "Testing valid login..."
./auth_api "admin" "password123"

echo "Testing SQL Injection..."
./auth_api "admin' --" "anything"
EOF
    chmod +x test_auth.sh

    chown -R user:user /home/user/auth_service
    chmod -R 777 /home/user
