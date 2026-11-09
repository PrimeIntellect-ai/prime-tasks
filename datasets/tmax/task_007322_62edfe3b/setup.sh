#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 g++ libsqlite3-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create the database
    sqlite3 /home/user/graph_data.db <<EOF
CREATE TABLE departments (
    id INTEGER PRIMARY KEY,
    name TEXT
);

CREATE TABLE users (
    id INTEGER PRIMARY KEY,
    name TEXT,
    department_id INTEGER,
    FOREIGN KEY(department_id) REFERENCES departments(id)
);

CREATE TABLE connections (
    user_id_1 INTEGER,
    user_id_2 INTEGER,
    connection_type TEXT,
    FOREIGN KEY(user_id_1) REFERENCES users(id),
    FOREIGN KEY(user_id_2) REFERENCES users(id)
);

INSERT INTO departments (id, name) VALUES (1, 'Engineering'), (2, 'Sales'), (3, 'HR');

INSERT INTO users (id, name, department_id) VALUES 
(101, 'Alice', 1),
(102, 'Bob', 2),
(103, 'Charlie', 1),
(104, 'Dave', 3);

-- Alice has 3 connections
INSERT INTO connections (user_id_1, user_id_2, connection_type) VALUES (101, 102, 'colleague'), (101, 103, 'colleague'), (101, 104, 'friend');
-- Bob has 1 connection
INSERT INTO connections (user_id_1, user_id_2, connection_type) VALUES (102, 101, 'colleague');
-- Charlie has 4 connections
INSERT INTO connections (user_id_1, user_id_2, connection_type) VALUES (103, 101, 'colleague'), (103, 102, 'friend'), (103, 104, 'friend'), (103, 103, 'self');
-- Dave has 0 connections

EOF

    # Create the initial buggy C++ code
    cat << 'EOF' > /home/user/etl_pipeline.cpp
#include <iostream>
#include <fstream>
#include <sqlite3.h>
#include <string>

static int callback(void* data, int argc, char** argv, char** azColName) {
    std::ofstream* out = static_cast<std::ofstream*>(data);
    for (int i = 0; i < argc; i++) {
        *out << (argv[i] ? argv[i] : "NULL");
        if (i < argc - 1) *out << ",";
    }
    *out << "\n";
    return 0;
}

int main() {
    sqlite3* db;
    char* zErrMsg = 0;
    int rc;

    rc = sqlite3_open("/home/user/graph_data.db", &db);
    if (rc) {
        std::cerr << "Can't open database: " << sqlite3_errmsg(db) << "\n";
        return 0;
    }

    std::ofstream outfile("/home/user/pipeline_out.csv");

    // BUG: Implicit cross join between users and departments.
    // BUG: Missing filter for connection count > 2.
    std::string sql = "SELECT u.id, u.name, d.name, COUNT(c.user_id_2) "
                      "FROM users u, departments d "
                      "LEFT JOIN connections c ON u.id = c.user_id_1 "
                      "GROUP BY u.id, u.name, d.name;";

    rc = sqlite3_exec(db, sql.c_str(), callback, (void*)&outfile, &zErrMsg);

    if (rc != SQLITE_OK) {
        std::cerr << "SQL error: " << zErrMsg << "\n";
        sqlite3_free(zErrMsg);
    }

    outfile.close();
    sqlite3_close(db);
    return 0;
}
EOF

    chown user:user /home/user/graph_data.db /home/user/etl_pipeline.cpp
    chmod -R 777 /home/user
